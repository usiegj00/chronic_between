#!/usr/bin/env ruby

# file: chronic_between.rb

require 'gitlab-chronic'
require 'date'
require 'app-routes'

class ChronicBetween
  include AppRoutes
  
  def initialize(x, debug: false)    
    
    @debug = debug
    @times = x.is_a?(String) ? x.split(/[,;&]/).map(&:strip) : x
    super()
  end
    
  def within?(raw_date)
    
    date = raw_date.respond_to?(:to_datetime) ? raw_date.to_datetime : raw_date
    @timezone = date.strftime("%z")
    @params[:timezone] = @timezone
    @year = date.year
    dates = []
    
    ranges(@params, date)
    
    negatives = '(not|except)\s+'
    times, closed_times = @times.partition {|x| !x[/^#{negatives}/]}
    closed_times.map!{|x| x[/^#{negatives}(.*)/,2]}
    
    dates = build times
    inside_range = dates.detect {|d1, d2| date.between? d1, d2}    
    
    neg_dates = build closed_times
    inside_restrictions = neg_dates.detect {|d1, d2| date.between? d1, d2}

    if inside_restrictions then
      return false 
    elsif closed_times.any? and times.empty? then
      return true
    elsif inside_range then
      return true
    else
      return false
    end
    
  end
    
  private
  
  def ranges(params, date)

    # e.g. Mon-Fri 9:00-16:30
    get %r{(\w+)-(\w+)\s+(\d[\w:]*)-(\d[\w:]*)$} do       
      d1, d2, t1, t2 = params[:captures]
      date_range_time_range(date, d1 ,d2, t1, t2)
    end
    
    # e.g. Mon-Fri 9:00 to 16:30
    get %r{(\w+)-(\w+)\s+(\d[\w:]*)\s+to\s+(\d[\w:]*)$} do       
      d1, d2, t1, t2 = params[:captures]
      date_range_time_range(date, d1 ,d2, t1, t2)
    end
    
    # e.g. 9:00-16:30 Mon-Fri 
    get %r{(\d[\w:]*)-(\d[\w:]*)\s+(\w+)-(\w+)$} do       
      t1, t2, d1, d2  = params[:captures]
      date_range_time_range(date, d1 ,d2, t1, t2)
    end
    
    # e.g. 9:00 to 16:30 Mon-Fri 
    get %r{(\d[\w:]*)\s+to\s+(\d[\w:]*)\s+(\w+)-(\w+)$} do       
      t1, t2, d1, d2  = params[:captures]
      date_range_time_range(date, d1 ,d2, t1, t2)
    end        

    get /today/i do
      date1 = DateTime.parse(Time.now.strftime("%d-%b-%y") + ' 00:00')
      [date1, date1 + 1]
    end

    # e.g. Saturday
    get %r{^(\w+)$} do
      day = params[:captures].first
      cdate1 = Chronic.parse(day, :now => (date - 1))
      date1 = DateTime.parse(cdate1.strftime("%d-%b-%y") + ' 00:00')
      [date1, date1 + 1]
    end

    # e.g. 3:45-5:15
    get %r{^(\d[\w:]*)\s*(?:-|to|and)\s*(\d[\w:]*)(?=\s*(daily|every day)?)} do
      t1, t2 = params[:captures]        
      time_range(date, t1, t2)
    end
    

    # e.g. Mon 3:45-5:15
    get %r{^(\w+)\s+(\d[\w:]*)\s*(?:-|to|and)\s*(\d[\w:]*)$} do                                                    
      d1, t1, t2 = params[:captures]        
      cdatetime_range(date, d1, t1, t2)
    end
        
    # e.g. 3:45-5:15 Mon
    get %r{^(\d[\w:]*)\s*(?:-|to|and)\s*(\d[\w:]*)\s+(\w+)$} do
      t1, t2, d1 = params[:captures]        
      cdatetime_range(date, d1, t1, t2)
    end
    

    # e.g. Mon-Wed
    get %r{^(\w+)\s*(?:-|to|and)\s*(\w+)$} do                                                    
      d1, d2 = params[:captures]        
      cdate2, n_days = latest_date_and_ndays(date, d1, d2)
      
      date2 = DateTime.parse(cdate2.strftime("%d-%b-%y") + ' 00:00')
      [date2 - n_days, date2]
    end
    
    # e.g. after 6pm
    get /^after\s+(\d[\w:]*)$/i do                                                    
      t1 = params[:captures].first
      date1 = DateTime.parse(date.strftime("%d-%b-%y ") + t1 + ' ' + params[:timezone])
      date2 = DateTime.parse((date + 1).strftime("%d-%b-%y ") + '00:00')      
      [date1, date2]
    end            

    # e.g. before 9pm
    get /^before\s+(\d[\w:]*)$/i do                                                    
      t1 = params[:captures].first
      date2 = DateTime.parse(date.strftime("%d-%b-%y ") + t1 + ' ' + params[:timezone])
      date1 = DateTime.parse(date.strftime("%d-%b-%y") + ' 00:00')
      [date1, date2]
    end

    # e.g. April 2nd - April 5th 12:00-14:00
    get %r{^(.*)\s+-\s+(.*)\s+(\d[\w:]*)-(\d[\w:]*)$} do                                                    
      d1, d2, t1, t2 = params[:captures]
      cdate1, cdate2 = [d1,d2].map {|d| Chronic.parse(d, :now => Time.local(@year))}
      n_days = ((cdate2 - cdate1) / 86400).to_i
      dates = 0.upto(n_days).map do |n|          
        x = cdate1.to_datetime + n
        datetime_range(x, t1, t2)
      end
    end            
    
    # e.g. April 5th - April 9th
    get %r{^(.*)\s+-\s+(.*)$} do                                                    
      
      puts 'route 600' if @debug
      d1, d2 = params[:captures]        
      cdate1, cdate2 = [d1,d2].map {|d| Chronic.parse(d, :now => Time.local(@year))}
      n_days = ((cdate2 - cdate1) / 86400).to_i
      
      date1 = DateTime.parse(cdate1.strftime("%d-%b-%y") + ' 00:00')
      date2 = DateTime.parse(cdate1.strftime("%d-%b-%y") + ' 23:59:59')
      [date1, date2 + n_days]
    end

    # e.g. April 5th
    get %r{^(.*)$} do
      day = params[:captures].first
      cdate1 = Chronic.parse(day, :now => Time.local(@year))
      date1 = DateTime.parse(cdate1.strftime("%d-%b-%y") + ' 00:00')
      date2 = DateTime.parse(cdate1.strftime("%d-%b-%y") + ' 23:59:59')
      [date1, date2]
    end

  end

  def build(times)
    
    times.inject([]) do |result, x|
      r = run_route(x.strip)
      r.first.is_a?(Array) ? result + r : result << r
    end
  end

  def date_range_time_range(date, d1, d2, t1, t2)
    cdate2, n_days = latest_date_and_ndays(date, d1, d2)
    dates = (n_days).downto(0).map do |n|          
      x = (cdate2.to_date - n)
      datetime_range(x, t1, t2)
    end
    return dates
  end
  
  def cdatetime_range(date, d1, t1, t2)
    x = Chronic.parse(d1, now: (date - 1))
    datetime_range(x, t1, t2)
  end  
  
  def latest_date_and_ndays(date, d1, d2)
    raw_date1 = Chronic.parse(d1, :context => :past,  :now => Time.local(@year))
    raw_date2 = Chronic.parse(d2, :now => raw_date1)
    cdate2 = Chronic.parse(d2, now: (date - 1))
    n_days = ((raw_date2 - raw_date1) / 86400).to_i

    [cdate2, n_days]
  end
  
  def time_range(date, t1, t2)
    [t1,t2].map {|t| DateTime.parse(date.strftime("%d-%b-%y ") + t + @timezone )}
  end
  
  alias datetime_range time_range
  
end
