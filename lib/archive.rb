#!/usr/bin/ruby

require 'rubygems'
require 'time'
require 'fileutils'

class ReportArchive
  def initialize report_dir, report_group, archive_dir=nil
    @report_dir = File.realpath(report_dir)
    @report_group = report_group
    @path = File.join(@report_dir, @report_group)
    @archive_dir = archive_dir || File.join(@report_dir, 'archive', report_group)
    FileUtils.mkpath @archive_dir unless Dir.exist? @archive_dir
    p @archive_dir
  end
  def run uuid=nil
    Dir.glob("#{@path}/#{uuid||'*'}").grep(Regexp.new("#{@path}/[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}")).each do |rdir|
      info = File.join(rdir, 'report.json')
      html = File.join(rdir, 'report.html')
      exist_html = File.exists?(html)
      exist_info = File.exists?(info)
      time = File.mtime(exist_info && info || (exist_html && html || rdir))
      tstr = time.strftime('%Y-%m-%d_%H:%M')
      m = time.to_date.month
      y = time.to_date.year
      ['html', 'pdf', 'csv', 'json'].each{|f| move_file(File.join(rdir, "report.#{f}"), m, y, tstr)}
    end
  end
  def move_file file, m, y, tstr
   return unless File.exist? file
   y_path = File.join(@archive_dir, y.to_s)
   m_path = File.join(y_path, m.to_s)
   ext = file.split('.').last
   ext_path = File.join(m_path, ext)
   Dir.mkdir y_path unless Dir.exist? y_path
   Dir.mkdir m_path unless Dir.exist? m_path
   Dir.mkdir ext_path unless Dir.exist? ext_path
   FileUtils.cp(file, File.join(ext_path, "#{tstr}_Report_#{@report_group}_#{file.split('/')[-2]}.#{ext}"))
  end
end
