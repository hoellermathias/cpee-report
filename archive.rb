#!/usr/bin/ruby

require 'rubygems'
require 'time'
require 'fileutils'

class Archive
  def initialize report_dir, report_group
    @report_dir = File.realpath(report_dir)
    @report_group = report_group
    @path = File.join(@report_dir, @report_group)
    @archive_dir = 'archive'
    @archive_path = File.join(@path, @archive_dir)
    Dir.mkdir @archive_path unless Dir.exist? @archive_path
  end
  def run
    Dir.chdir @path
    Dir.glob('*').grep(/[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}/).each do |rdir|
      html = File.join(rdir, 'report.html')
      pdf = File.join(rdir, 'report.pdf')
      csv = File.join(rdir, 'report.csv')
      time = File.mtime(html)
      tstr = time.strftime('%Y-%m-%d_%H:%M')
      m = time.to_date.month
      y = time.to_date.year
      [html, pdf, csv].each{|f| move_file(File.join(@path, f), m, y, tstr)}
    end
  end
  def move_file file, m, y, tstr
   return unless File.exist? file
   y_path = File.join(@archive_path, y.to_s)
   m_path = File.join(y_path, m.to_s)
   ext = file.split('.').last
   ext_path = File.join(m_path, ext)
   Dir.mkdir y_path unless Dir.exist? y_path
   Dir.mkdir m_path unless Dir.exist? m_path
   Dir.mkdir ext_path unless Dir.exist? ext_path
   FileUtils.cp(file, File.join(ext_path, "#{tstr}_Report_#{@report_group}_#{file.split('/')[-2]}.#{ext}"))
  end
end
