# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "socket"

# This output allows you to pull metrics from your logs and ship them to
# opentsdb. Opentsdb is an open source tool for storing and graphing metrics.
#
class LogStash::Outputs::Opentsdb < LogStash::Outputs::Base
  config_name "opentsdb"

  # The address of the opentsdb server.
  config :host, :validate => :string, :default => "localhost"

  # The port to connect on your graphite server.
  config :port, :validate => :number, :default => 4242

  # The metric(s) to use. This supports dynamic strings like %{source_host}
  # for metric names and also for values. This is an array field with key
  # of the metric name, value of the metric value, and multiple tag,values . Example:
  # [source,ruby]
  #     [
  #       "%{host}/uptime",
  #       %{uptime_1m} " ,
  #       "hostname" ,
  #       "%{host}
  #       "anotherhostname" ,
  #       "%{host}
  #     ]
  #
  # The value will be coerced to a floating point value. Values which cannot be
  # coerced will zero (0)
  config :metrics, :validate => :array, :required => true

  # Use millisecond resolution for timestamp (supported by OpenTSDB version >=2.0).
  # See http://opentsdb.net/docs/build/html/user_guide/writing.html#timestamps
  config :use_millis, :validate => :boolean, :default => false

  def register
    if use_millis
      # concatenate seconds and milliseconds into 13-digit timestamp
      @time_format = "%{+%s}%{+SSS}"
    else
      @time_format = "%{+%s}"
    end

    connect
  end # def register

  def connect
    # TODO(sissel): Test error cases. Catch exceptions. Find fortune and glory.
    begin
      @socket = TCPSocket.new(@host, @port)
    rescue Errno::ECONNREFUSED => e
      @logger.warn("Connection refused to opentsdb server, sleeping...",
                   :host => @host, :port => @port)
      sleep(2)
      retry
    end
  end # def connect

  public
  def receive(event)
    

    # Opentsdb message format: put metric timestamp value tagname=tagvalue tag2=value2\n

    # Catch exceptions like ECONNRESET and friends, reconnect on failure.
    begin
      name = metrics[0]
      value = metrics[1]
      tags = metrics[2..-1]

      # The first part of the message
      message = ['put',
                 event.sprintf(name),
                 event.sprintf(@time_format),
                 event.sprintf(value),
      ].join(" ")

      # If we have have tags we need to add it to the message
      event_tags = []
      unless tags.nil?
        Hash[*tags.flatten].each do |tag_name,tag_value|
          # Interprete variables if neccesary
          real_tag_name = event.sprintf(tag_name)
          real_tag_value =  event.sprintf(tag_value)
          event_tags << [real_tag_name , real_tag_value ].join('=')
        end
        message+=' '+event_tags.join(' ')
      end

      # TODO(sissel): Test error cases. Catch exceptions. Find fortune and glory.
      begin
        @logger.debug("Write message to opentsdb", :msg => message)
        @socket.puts(message)
      rescue Errno::EPIPE, Errno::ECONNRESET => e
        @logger.warn("Connection to opentsdb server died",
                     :exception => e, :host => @host, :port => @port)
        sleep(2)
        connect
      end

      # TODO(sissel): resend on failure
      # TODO(sissel): Make 'resend on failure' tunable; sometimes it's OK to
      # drop metrics.
    end # @metrics.each
  end # def receive
end # class LogStash::Outputs::Opentsdb
