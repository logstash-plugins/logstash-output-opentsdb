require_relative 'support/server'

class LogStash::Outputs::Opentsdb
  attr_reader :socket

  # Mock connect to return a fake server
  def connect
    @socket = Mocks::Server.new
  end
end
