require 'cpee/value_helper'
require 'date'

class Event
  attr_reader :topic, :event, :activity_uuid, :activity_id

  def initialize(topic='nil', event='nil', nots={'content' =>{'activity-uuid' => 'init_snippet', 'activity' => nil, 'timestamp' => Time.now}})
    @topic         = topic
    @event         = event
    @nots          = nots
    @activity_uuid = nots.dig('content', 'activity-uuid')
    @activity_id   = nots.dig('content', 'activity')
  end
  def name
    "#{@activity_id}:#{@topic}:#{@event}"
  end
  def to_s
    JSON.pretty_generate [@topic,@event,@activity_uuid,@activity_id]
  end
  def get_data_s d_name
    case d_name.first
    when 'timestamp'
      DateTime.parse(@nots['timestamp']).strftime('%d.%m.%Y um %H:%M:%S')
    else
      case @topic
      when 'dataelements'
          @nots.dig('content', 'values', *d_name.map{|x| (Integer x rescue nil) || x.to_s }) || '--'
      else
        @nots.dig(*d_name.map(&:to_s)) || @nots.dig(*d_name.unshift('content').map(&:to_s)) || '--'
      end
    end
  end
  #check if dataelements change event is relevant (this event changed the dataelement)
  def is_relevant? d_name
    return !!@nots.dig('content', 'changed')&.include?(d_name.first) if @topic == 'dataelements' && d_name.first != 'timestamp'
    true
  end
end
