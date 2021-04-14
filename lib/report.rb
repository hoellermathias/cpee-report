require 'fileutils'
require_relative 'event'

class Report
  attr_accessor :group, :id
  def initialize group, opts, fname, template=nil, nots
    @const_snippets={}
    @opts = opts
    @group = group
    @id = fname
    @dirname = File.join(opts[:report_dir], group, fname)
    FileUtils.mkdir_p("#{@dirname}/snippets/")
    FileUtils.mkdir_p("#{@dirname}/events/")

    rname = File.join(@dirname,'report.html')
    File.write(rname,template) unless File.exist?(rname)
    File.write(rname.gsub('.html', '.json'),JSON.pretty_generate(nots)) unless File.exist?(rname.gsub('.html', '.json'))
  end
  def add_snippet snippet, event
    return if File.exists?(File.join(@dirname,'snippets',event.activity_uuid))
    snippet.scan(/%(\w*:\w+:[\w+|:]*)%/).each do |match|
      if match.first[0] == ':' && event.activity_id
        new_event_str = event.activity_id.to_s + match.first
        snippet.gsub! "%#{match.first}%", "%#{new_event_str}%"
        match[0] = new_event_str
      end
      FileUtils.touch(File.join(@dirname,'events',"#{match.first}-#{event.activity_uuid}"))
    end
    File.write(File.join(@dirname,'snippets',event.activity_uuid),snippet)
    report = File.read(File.join(@dirname,'report.html'))
    report.gsub! '</body>', "<snippet>#{event.activity_uuid}</snippet>\n</body>"
    File.write(File.join(@dirname,'report.html'), report)
  end
  def add_csv csv, event
    csv.scan(/%(\w*:\w+:[\w+|:]*)%/).each do |match|
      FileUtils.touch(File.join(@dirname,'events',"#{match.first}-csv"))
    end
    @csv_str = csv.strip.split("\n").last
    csv_fn = File.join(@dirname,'report.csv')
    File.write(csv_fn ,csv.strip.split("\n")[0..-2].join("\n")) unless File.exists?(csv_fn)
    @csv_temp = @csv_str.dup
  end
  def event_done event
    #event is part of a snippet
    events =  Dir.glob(File.join(@dirname,'events',event.name + '*'))
    events += Dir.glob(File.join(@dirname,'events',event.name.gsub(/a\d+:/,':') + '*'))
    p event.name.gsub(/a\d+:/,':')
    p events
    return unless events
    events.each do |e|
      puts e
      event_elem_id, snippet = e.split('/').last.split('-')
      event_elem = event_elem_id.split(':')
      p 'event relevant?'
      p event.is_relevant? event_elem[3..-1]
      next unless event.is_relevant? event_elem[3..-1]
      if snippet == 'csv'
        add_str=''
        begin
          add_str << "\n#{@csv_str}"
          @csv_str = @csv_temp.dup
        end unless @csv_str.include? event_elem_id
        @csv_str.gsub! "%#{event_elem_id}%", event.get_data_s(event_elem[3..-1]).to_s
        begin
          add_str << "\n#{@csv_str}"
          @csv_str = @csv_temp.dup
        end unless /%(\w*:\w+:[\w+|:]*)%/.match(@csv_str)
        snippet_path = File.join(@dirname,'report.csv')
        #puts add_str
        #puts @csv_str
        #puts @csv_temp
        File.open(snippet_path, "a"){|f| f.write("#{add_str}")} unless add_str.empty?
      else
        snippet_path = File.join(@dirname,'snippets',snippet)
        File.open(snippet_path, File::RDWR) do |f|
          f.flock(File::LOCK_EX)
          f_cont = f.read
          const_part = /<const>((.|\s)*)<\/const>/.match(f_cont)&.captures&.first
          @const_snippets[snippet_path] = const_part if const_part && !@const_snippets.include?(snippet_path)
          snippet_content = f_cont.gsub "%#{event_elem_id}%", event.get_data_s(event_elem[3..-1]).to_s
          f.rewind
          f.write(snippet_content)
          f.flush
          f.truncate(f.pos)
          File.delete(e) unless const_part
          finalize_snippet(snippet, snippet_content, snippet_path) unless Dir.glob(File.join(@dirname,'events', "/*-#{snippet}")).any?
        end
      end
    end
    @const_snippets.each do |path, content|
      File.open(path, File::RDWR) do |f|
        f.flock(File::LOCK_EX)
        f_cont = f.read
        next if /%(\w*:\w+:[\w+|:]*)%/.match(/<const>((.|\s)*)<\/const>/.match(f_cont)&.captures&.first)
        f_cont.slice! '<const>'
        snippet_content = f_cont.gsub '</const>', '<const>' + content + '</const>'
        f.rewind
        f.write(snippet_content)
        f.flush
        f.truncate(f.pos)
      end
    end
  end
  def finalize_snippet snippet_id, content, path
    rep_path = File.join(@dirname,'report.html')
    @const_snippets.delete(path)
    File.open(rep_path, File::RDWR) do |f|
      f.flock(File::LOCK_EX)
      rep_content = f.read.gsub "<snippet>#{snippet_id}</snippet>", content.sub(/<const>((.|\s)*)<\/const>/, '')
      f.rewind
      f.write(rep_content)
      f.flush
      f.truncate(f.pos)
    end
  end
  def finalize_csv
    snippet_path = File.join(@dirname,'report.csv')
    File.open(snippet_path, "a"){|f| f.write("\n#{@csv_str}")} if @csv_str != @csv_temp
  end
  def finalize
    snippets = File.join(@dirname,'snippets')
    events = File.join(@dirname,'events')
    Dir.glob(File.join(snippets,'*')).each do |snippet_path|
      snippet_id = snippet_path.split('/').last
      snippet_content = File.read snippet_path
      finalize_snippet snippet_id, snippet_content, snippet_path
    end
    FileUtils.remove_dir snippets
    FileUtils.remove_dir events
    finalize_csv
  end
  def send_email report_url, a
    a['subject'] += Time.new.tap{|x| str=x.strftime('%d.%m.%Y %H:%M:%S'); day=['Sonntag', 'Montag','Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'][x.strftime('%w').to_i]; break "#{day}, #{str}"}
    a['subject'] += "\nContent-type: text/html"
    b = {to: a['to'], subject: a['subject'], text: a['text'].gsub('%link_to_report%', report_url)}
    Typhoeus.post @opts[:mail_server], body: b
  end
  def send_email_attachment report_location, a
    pdf = File.read(report_location)
    fn = "Report_#{Time.now.strftime('%d.%m.%Y')}.pdf"
    encoded_content = [pdf].pack("m")   # base64

    marker = "AUNIQUEMARKER"

    a['subject'] += Time.new.tap{|x| str=x.strftime('%d.%m.%Y %H:%M:%S'); day=['Sonntag', 'Montag','Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'][x.strftime('%w').to_i]; break "#{day}, #{str}"}
    a['subject'] += <<~EOS

    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary = #{marker}
    --#{marker}
   EOS

    a['subject'] += <<~EOS
    Content-Type: text/html; charset=UTF-8
    Content-Transfer-Encoding:8bit

    #{a['text']}
    --#{marker}
    EOS

    a['subject'] += <<~EOS
    Content-Type: application/pdf; name = "#{fn}"
    Content-Transfer-Encoding:base64
    Content-Disposition: attachment; filename = "#{fn}"

    #{encoded_content}
    EOS #if pdf

    #a['subject'] += <<~EOS
    #Content-Type: application/pdf; name = "#{fn}"
    #Content-Transfer-Encoding:base64
    #Content-Disposition: attachment; filename = "#{fn}"

    ##{encoded_content}
    #EOS #if csv


    a['subject'] += <<~EOS
    --#{marker}--
    EOS

    b = {to: a['to'], subject: a['subject'], text: ''}
    Typhoeus.post @opts[:mail_server], body: b
  end
end
