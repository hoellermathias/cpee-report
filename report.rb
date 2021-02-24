#!/usr/bin/ruby

# This file is part of EVVA-REPORTS
#
# EVVA-REPORTS is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# EVVA-REPORTS is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# EVVA-REPORTS (file LICENSE in the main directory).  If not, see
# <http://www.gnu.org/licenses/>.

require 'rubygems'
require 'json'
require 'riddl/server'
require 'time'
require 'pdfkit'
require_relative 'lib/report'
require_relative 'lib/event'

class Handler < Riddl::Implementation #{{{
  @@reports = {}
  def response
    opts = @a[0]
    nots = JSON.parse(@p[3].class == Riddl::Parameter::Simple ? @p[3].value :  @p[3].value.read)

    #return unless @p[1].value == 'state' && @p[2].value == 'change' && (nots.dig('content','state') == 'running' || nots.dig('content','state') == 'finished')

    # { "cpee"=>"https://centurio.work/flow-test/engine",
    #   "instance-url"=>"https://centurio.work/flow-test/engine/11",
    #   "instance-uuid"=>"d8454fba-8981-45e9-999a-bf8eb98c2397",
    #   "instance-name"=>"test_email_report",
    #   "instance"=>11,
    #   "topic"=>"activity",
    #   "type"=>"event",
    #   "name"=>"calling",
    #   "timestamp"=>"2020-10-15T15:44:24.650+02:00",
    #   "content"=>{
    #     "activity_uuid"=>"8089191222b307c56bf8d790eecc5f78",
    #     "label"=>"timeout 2",
    #     "activity"=>"a2",
    #     "passthrough"=>nil,
    #     "endpoint"=>"http://gruppe.wst.univie.ac.at/~mangler/services/timeout.php",
    #     "parameters"=>{"label"=>"timeout 2", "method"=>"post", "arguments"=>[{"name"=>"timeout", "value"=>"1"}],
    #     "sensors"=>nil,
    #     "report"=>{"url"=>"https://centurio.work/customers/evva/report/galvanik/timeout.html"}},
    #     "attributes"=>{"status"=>"model", "uuid"=>"d8454fba-8981-45e9-999a-bf8eb98c2397", "report"=>"https://centurio.work/customers/evva/report/report.html", "creator"=>"Mathias Hoellerer", "author"=>"Mathias Hoellerer", "modeltype"=>"CPEE", "theme"=>"default", "info"=>"test_email_report", "report_email"=>"{\"to\": \"mathias.hoeller@univie.ac.at\", \"subject\": \"test process\", \"text\": \"https://centurio.work/customers/evva/report/email_test/email.html\"}"}
    #    }
    # }
    instance_id = nots['instance-uuid']
    report = @@reports[instance_id]
    unless report
      return unless @p[1].value == 'state' && @p[2].value == 'change' && nots.dig('content','state') == 'running' && (nots.dig('content','attributes','report') || nots.dig('content','attributes','report_csv'))
      begin
        attribute_uri = File.join(nots['instance-url'],'properties','attributes','report')
        template_uri = Typhoeus.get(attribute_uri, followlocation: true).response_body
        #puts template_uri
      rescue Exception => e
        return
      end
      begin
        template = Typhoeus.get(template_uri, followlocation: true).response_body
        template.gsub! '%date%', Time.new.tap{|x| str=x.strftime('%d.%m.%Y %H:%M:%S'); day=['Sonntag', 'Montag','Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'][x.strftime('%w').to_i]; break "#{day}, #{str}"}
      rescue Exception => e
        p 'error loading the template: '+e.message
        template = '<p>error while loading the report template: check the instance attribute \"report\"</p><body></body>'
      end
      group = nots.dig('content','attributes','report_group') || 'default'
      report = @@reports[instance_id] = Report.new group, opts, instance_id, template
      #read init snippet and add it to the report
      init_snippet_uri = nots.dig('content','attributes','report_init_snippet')
      begin
        init_snippet = Typhoeus.get(init_snippet_uri, followlocation: true).response_body
        report.add_snippet init_snippet, Event.new
      rescue Exception => e
        puts 'error loading the init_snippet: ' + e.full_message
      end if init_snippet_uri
      #read csv template and add it to the report
      csv_uri = nots.dig('content','attributes','report_csv')
      begin
        csv = Typhoeus.get(csv_uri, followlocation: true).response_body
        report.add_csv csv, Event.new
      rescue Exception => e
        puts 'error loading the csv template: ' + e.full_message
      end if csv_uri
    end
    return unless report
    event = Event.new @p[1].value, @p[2].value, nots  #report.add_event params
    if event.topic == "activity" || event.topic == "dataelements"
      if event.event == "calling" && nots.dig("content" ,"parameters", "report", "url")
        snippet_url = nots.dig("content" ,"parameters", "report", "url")
        snippet = Typhoeus.get(snippet_url, followlocation: true).response_body
        report.add_snippet snippet, event
      end
      report.event_done event
    elsif event.topic == 'state' and event.event == 'change' and nots.dig('content', 'state') == 'finished'
      report.finalize
      @@reports.delete report.id
      begin
        attribute_uri = File.join(nots["instance-url"],'properties','attributes','report_email','/')
        attribute = Typhoeus.get(attribute_uri, followlocation: true).response_body
        unless attribute.empty? then
          a = JSON.parse(attribute)
          a['text'] = Typhoeus.get(a['text'], followlocation: true).tap{|r| break r.response_code == 200 ? r.response_body : 'Predefinied Email Content not found. \n%link_to_report%'} if a['text'] =~ URI::regexp
          report_path = File.join(__dir__ ,opts[:report_dir], report.group, report.id, 'report.pdf')
          kit = PDFKit.new(File.new(report_path[0..-5]+'.html'), :margin_top => '0.5in', :margin_bottom => '0.5in')
          file = kit.to_file(report_path)
          report.send_email_attachment report_path, a
        end
      rescue Exception => e
        puts 'report_email failed ' + e.message + '  ' + e.backtrace.join("\n")
      end
    end
  end
end #}}}

class GetNames < Riddl::Implementation #{{{
  def response
    opts = @a[0]
    list = Dir.children(opts[:report_dir]).map { |e|
    id = File.join(opts[:report_dir], e)
    "<li><a href=\"#{e}\">#{e}</a> #{File.mtime(id)}"
    }
    list.unshift(%{
    <head>
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js"></script>
    </head>
    <body>
    <ul>})

    list.push('</ul></body>')
    Riddl::Parameter::Complex.new('list', 'text/html', list.join(''))
  end
end #}}}

class GetUuids < Riddl::Implementation #{{{
  def response
    opts = @a[0]
    list = Dir.children(File.join(opts[:report_dir], @r)).map { |e|
      id = File.join(opts[:report_dir], @r, e)
      %{<tr>
        <td>#{e}</td>
        <td><a href=\"#{File.join(@r, e, 'report.html')}\">HTML</a></td>
        <td><a href=\"#{File.join(@r, e, 'report.pdf')}\">PDF</a></td>
        <td>#{File.mtime(id)}</td>
       </tr>
      }
    }
    list.unshift(%{
    <head>
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js"></script>
    </head>
    <body>
    <table>
      <thead>
        <tr>
          <th>Process Instance Id</th>
          <th>HTML</th>
          <th>PDF</th>
          <th>TIME</th>
        </tr>
      </thead>
      <tbody>})

    list.push('</tbody></body>')
    Riddl::Parameter::Complex.new('list', 'text/html', list.join(''))
  end
end #}}}

class GetHtml < Riddl::Implementation #{{{
  def response
    opts = @a[0]
    report_path = File.join(opts[:report_dir], @r)
    Riddl::Parameter::Complex.new('report', 'text/html', File.read(report_path))
  end
end #}}}

class GetPdf < Riddl::Implementation
  def response
    opts = @a[0]
    report_path = File.join(opts[:report_dir], @r)
    kit = PDFKit.new(File.new(report_path[0..-5]+'.html'), :margin_top => '0.5in', :margin_bottom => '0.5in')
    file = kit.to_file(report_path)
    Riddl::Parameter::Complex.new('report-pdf', 'application/pdf', file)
  end
end

Riddl::Server.new('report.xml', :port => 9321) do |opts|
  accessible_description true
  cross_site_xhr true

  opts[:report_dir] ||= 'reports'
  opts[:report_url] ||= 'https://centurio.work/customers/evva/reportservice/report/'
  opts[:mail_server] ||= 'http://localhost:9313'

  interface 'events' do
    run Handler, opts if post 'event'
  end

  interface 'delivery' do
    run GetNames, opts if get
    on resource '\w+' do
      run GetUuids, opts if get
      on resource '[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}' do
        run Delete if delete
        on resource 'report.html' do
          run GetHtml, opts if get
        end
        on resource 'report.pdf' do
          run GetPdf, opts if get
        end
      end
    end
  end
end.loop!
