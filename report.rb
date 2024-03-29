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
require 'riddl/client'
require 'time'
require 'pdfkit'
require 'zip'
require_relative 'lib/report'
require_relative 'lib/event'
require_relative 'lib/archive'

PDFKit.configure do |config|
  config.wkhtmltopdf = '/usr/bin/wkhtmltopdf'
end

module PDFprint
  def PDFprint.prepare_html_print report_path
    tempf = report_path+'.html'
    File.write(tempf, File.read(report_path[0..-5]+'.html').gsub(/%(\w*:\w+:[\w+|:]*)%/, ''))
    kit = PDFKit.new(File.new(tempf), :margin_top => '0.5in', :margin_bottom => '0.5in')
    kit.to_file(report_path)
  end
end

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
    #{
    #"cpee": "https://centurio.evva.com/flow/engine/",
    #"instance-url": "https://centurio.evva.com/flow/engine/9876",
    #"instance-uuid": "b15ba7a1-c85d-4dd8-a46b-740fb11a30f5",
    #"instance-name": "Frames",
    #"instance": 9876,
    #"topic": "activity",
    #"type": "event",
    #"name": "calling",
    #"timestamp": "2021-11-10T19:12:25.480+01:00",
    #"content": {
    #    "activity-uuid": "25deb0e09941664e7b93b58df5374181",
    #    "label": "button",
    #    "activity": "a5",
    #    "passthrough": null,
    #    "endpoint": "https-put://centurio.evva.com/out/frames/galvanik",
    #    "parameters": {
    #        "label": "button",
    #        "arguments": [
    #            {
    #                "name": "type",
    #                "value": "wait"
    #            },
    #            {
    #                "name": "lx",
    #                "value": "0"
    #            },
    #            {
    #                "name": "ly",
    #                "value": "9"
    #            },
    #            {
    #                "name": "x_amount",
    #                "value": "10"
    #            },
    #            {
    #                "name": "y_amount",
    #                "value": "1"
    #            },
    #            {
    #                "name": "button",
    #                "value": null
    #            },
    #            {
    #                "name": "style",
    #                "value": null
    #            },
    #            {
    #                "name": "urls",
    #                "value": "[ { \"lang\": \"de-at\", \"url\": \"https://centurio.evva.com/departments/galvanik/galwass/framesui/cancel_button.html\" } ]"
    #            },
    #            {
    #                "name": "default",
    #                "value": null
    #            }
    #        ]
    #    },
    #    "annotations": {
    #        "_timing": {
    #            "_timing_weight": null,
    #            "_timing_avg": null,
    #            "explanations": null
    #        },
    #        "_notes": {
    #            "_notes_general": null
    #        },
    #        "report": {
    #            "url": null
    #        }
    #    },
    #    "attributes": {
    #        "author": "Mathias Hoellerer",
    #        "department": "galvanik",
    #        "creator": "Florian Pauker",
    #        "modeltype": "CPEE",
    #        "design_stage": "production",
    #        "design_dir": "",
    #        "theme": "extended",
    #        "uuid": "b15ba7a1-c85d-4dd8-a46b-740fb11a30f5",
    #        "info": "Frames"
    #    }
    #}
    #}
    instance_id = nots['instance-uuid']
    report = @@reports[instance_id]
    unless report
      return unless (@p[1].value == 'state' && @p[2].value == 'change' && nots.dig('content','state') == 'running' && (nots.dig('content','attributes','report') || nots.dig('content','attributes','report_csv'))) || Dir.glob(File.join(__dir__ ,opts[:report_dir], '*', instance_id)).any?
      begin
        attribute_uri = File.join(nots['instance-url'],'properties','attributes','report')
        status, res = Riddl::Client.new(attribute_uri).get
        template_uri = res[0].class == Riddl::Parameter::Simple ? res[0].value :  res[0].value.read
        #puts template_uri
      rescue Exception => e
        puts e.message
        return
      end
      begin
        status, res = Riddl::Client.new(template_uri).get
        template = res[0].class == Riddl::Parameter::Simple ? res[0].value :  res[0].value.read
        template.gsub! '%date%', Time.new.tap{|x| str=x.strftime('%d.%m.%Y %H:%M:%S'); day=['Sonntag', 'Montag','Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'][x.strftime('%w').to_i]; break "#{day}, #{str}"}
      rescue Exception => e
        p 'error loading the template: '+e.message
        template = '<p>error while loading the report template: check the instance attribute \"report\"</p><body></body>'
      end
      group = nots.dig('content','attributes','report_group') || 'default'
      report = @@reports[instance_id] = Report.new group, opts, instance_id, template, nots
      #read init snippet and add it to the report
      init_snippet_uri = nots.dig('content','attributes','report_init_snippet')
      begin
        status, res = Riddl::Client.new(init_snippet_uri).get
        init_snippet = res[0].class == Riddl::Parameter::Simple ? res[0].value :  res[0].value.read
        p init_snippet
        report.add_snippet init_snippet, Event.new
        pp init_snippet
      rescue Exception => e
        puts 'error loading the init_snippet: ' + e.full_message
      end if init_snippet_uri

      #read csv template and add it to the report
      csv_uri = nots.dig('content','attributes','report_csv')
      begin
        status, res = Riddl::Client.new(csv_uri).get
        csv = res[0].class == Riddl::Parameter::Simple ? res[0].value :  res[0].value.read
        report.add_csv csv, Event.new
      rescue Exception => e
        puts 'error loading the csv template: ' + e.full_message
      end if csv_uri
    end
    return unless report
    event = Event.new @p[1].value, @p[2].value, nots  #report.add_event params
    if event.topic == "activity" || event.topic == "dataelements"
      if event.event == "calling" && nots.dig("content" ,"annotations", "report", "url")
        snippet_url = nots.dig("content" ,"annotations", "report", "url")
        status, res = Riddl::Client.new(snippet_url).get
        snippet = res[0].class == Riddl::Parameter::Simple ? res[0].value :  res[0].value.read
        report.add_snippet snippet, event
      end
      report.event_done event
    elsif event.topic == 'state' and event.event == 'change' and nots.dig('content', 'state') == 'finished'
      report.finalize
      report_path = File.join(__dir__ ,opts[:report_dir], report.group, report.id, 'report.pdf')
      PDFprint.prepare_html_print report_path
      a = ReportArchive.new opts[:report_dir], report.group, opts['report_archive']&.dig(report.group)
      a.run report.id
      @@reports.delete report.id
      begin
        attribute_uri = File.join(nots["instance-url"],'properties','attributes','report_email','/')
        begin
          status, res = Riddl::Client.new(attribute_uri).get
          attribute = res[0].class == Riddl::Parameter::Simple ? res[0].value :  res[0].value.read if status < 400
          unless status >= 400 || attribute.empty? then
            a = JSON.parse(attribute)
            if a['text'] =~ URI::regexp then
              status, res = Riddl::Client.new(a['text']).get
              res = res[0].class == Riddl::Parameter::Simple ? res[0].value :  res[0].value.read if status < 400
              a['text'] = status == 200 ? res : "Predefinied Email Content not found. \n%link_to_report%"
            end
            report.send_email_attachment report_path, a
          end
        end if attribute_uri
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
    list = Dir.children(File.join(opts[:report_dir], @r))
              .sort_by { |x| File.mtime(File.exists?(File.join(opts[:report_dir], @r, x, 'report.json')) ? File.join(opts[:report_dir], @r, x, 'report.json') : File.exists?(File.join(opts[:report_dir], @r, x, 'report.html')) ? File.join(opts[:report_dir], @r, x, 'report.html') : File.join(opts[:report_dir], @r, x)) }
              .filter_map { |e|
                id = File.join(opts[:report_dir], @r, e)
                next unless File.directory? id
                csv = File.join('..', @r, e, 'report.csv')
                html = File.join('..', @r, e, 'report.html')
                info = File.join('..', @r, e, 'report.json')
                next unless File.exist?(File.join(opts[:report_dir], @r, e, 'report.html'))
                csv_exists = File.exist?(File.join(opts[:report_dir], @r, e, 'report.csv'))
                info_exists = File.exist?(File.join(opts[:report_dir], @r, e, 'report.json'))
                %{<tr>
                  <td>#{e}</td>
                  <td><a href=\"#{html}\">HTML</a></td>
                  <td><a href=\"#{File.join('..', @r, e, 'report.pdf')}\">PDF</a></td>
                  <td>#{csv_exists && '<a href='+csv+'>CSV</a>' || '<p>---</p>'}</td>
                  <td>#{info_exists && '<a href='+info+'>INFO</a>' || '<p>---</p>'}</td>
                  <td>#{File.mtime(File.join(id, info_exists ? 'report.json' : 'report.html'))}</td>
                 </tr>
                }
              }
    list.unshift(%{
    <head>
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.1/jquery.min.js"></script>
    </head>
    <body>
    <p><a href="reports.zip">Download all CSVs and PDFs as Zip</a></p>
    <p><a href="archive">Archive Reports</a></p>
    <table>
      <thead>
        <tr>
          <th>Process Instance Id</th>
          <th>HTML</th>
          <th>PDF</th>
          <th>CSV</th>
          <th>INFO</th>
          <th>TIME</th>
        </tr>
      </thead>
      <tbody>})

    list.push('</tbody></table></body>')
    Riddl::Parameter::Complex.new('list', 'text/html', list.join(''))
  end
end #}}}

class GetINFO < Riddl::Implementation #{{{
  def response
    opts = @a[0]
    report_path = File.join(opts[:report_dir], @r)
    Riddl::Parameter::Complex.new('report-info', 'application/json', File.read(report_path), "#{@r[1]}.json")
  end
end #}}}

class GetCSV < Riddl::Implementation #{{{
  def response
    opts = @a[0]
    report_path = File.join(opts[:report_dir], @r)
    Riddl::Parameter::Complex.new('report-csv', 'text/csv', File.read(report_path), "#{@r[1]}.csv")
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
    file = PDFprint.prepare_html_print report_path
    Riddl::Parameter::Complex.new('report-pdf', 'application/pdf', file, "#{@r[1]}.pdf")
  end
end

class RunArchive < Riddl::Implementation
  def response
    opts = @a[0]
    archive = ReportArchive.new File.join(opts[:basepath], opts[:report_dir]), @r[0], opts['report_archive']&.dig(@r[0])
    archive.run
    @headers << Riddl::Header.new("Location",'..')
    @status = 303
  end
end

class GetPdfZip < Riddl::Implementation
  def response
    opts = @a[0]
    zn = File.join(opts[:report_dir], @r[0..-2], 'reports.zip')
    File.delete zn if File.exist? zn
    file = Zip::File.new(zn, true)
    ['pdf', 'csv'].each do |ext|
      Dir.glob(File.join(opts[:report_dir], @r[0..-2], "*/report.#{ext}")).map do |x|
        date = File.mtime(x.gsub(".#{ext}", '.html')).then{|x| x.strftime('%Y-%m-%d_%H:%M')}
        name = "#{ext}/#{date}.#{ext}"
        it = 1
        while file.find_entry name do
          name = "#{ext}/#{date}_#{it}.#{ext}"
          it += 1
        end
        file.add(name, x)
      end
    end
    file.close
    z = File.open(zn)
    Riddl::Parameter::Complex.new('report-zip', 'application/zip', z)
  end
end

Riddl::Server.new('report.xml', :port => 9321) do |opts|
  accessible_description true
  cross_site_xhr true
  p opts

  opts[:report_dir] ||= 'reports'
  opts[:report_url] ||= 'https://centurio.evva.com/departments/galvanik/reportservice/report/'
  opts[:mail_server] ||= 'http://localhost:9313'
  #opts[:archive_dir] ||= '/srv/Galvanik_Aufbereitung'

  interface 'events' do
    run Handler, opts if post 'event'
  end

  interface 'delivery' do
    run GetNames, opts if get
    on resource '\w+' do
      run GetUuids, opts if get
      on resource 'reports.zip' do
        run GetPdfZip, opts if get
      end
      on resource 'archive' do
        run RunArchive, opts if get
      end
      on resource '[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}' do
        run Delete if delete
        on resource 'report.html' do
          run GetHtml, opts if get
        end
        on resource 'report.pdf' do
          run GetPdf, opts if get
        end
        on resource 'report.csv' do
          run GetCSV, opts if get
        end
        on resource 'report.json' do
          run GetINFO, opts if get
        end
      end
    end
  end
end.loop!
