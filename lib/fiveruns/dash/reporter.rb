require 'thread'

module Fiveruns::Dash

  class ShutdownSignal < ::Exception; end
    
  class Reporter
    
    attr_accessor :interval
    attr_reader :started_at
    def initialize(session, interval = 60)
      @session = session
      @interval = interval
    end
    
    def revive!
      return if !started? || foreground?
      start if !@thread || !@thread.alive?
    end
    
    def alive?
      @thread && @thread.alive? && started?
    end

    def start(run_in_background = true)
      restarted = @started_at ? true : false
      unless defined?(@started_at)
        @started_at = ::Fiveruns::Dash::START_TIME
      end
      setup_for run_in_background
      if @background
        @thread = Thread.new { run(restarted) }
      else
        # Will it be run in foreground?
        run(restarted)
      end
    end
    
    def started?
      @started_at
    end
    
    def foreground?
      started? && !@background
    end
    
    def background?
      started? && @background
    end
    
    def send_trace(trace)
      if trace.data
        payload = TracePayload.new(trace)
        Fiveruns::Dash.logger.debug "Sending trace: #{payload.to_fjson}"
        Thread.new { Update.new(payload).store(*update_locations) }
      else
        Fiveruns::Dash.logger.debug "No trace to send"      
      end
    end
    
    def ping
      payload = PingPayload.new(@session.info, @started_at)
      Update.new(payload).ping(*update_locations)
    end

    def stop
      @thread && @thread.alive? && @thread.raise(ShutdownSignal.new)
    end

    def secure!
      @update_locations = %w(https://dash-collector.fiveruns.com https://dash-collector02.fiveruns.com)
    end

    #######
    private
    #######

    TRAPS = {}

    def install_signals
      %w(INT TERM).each do |sym|
        TRAPS[sym] = Signal.trap(sym) do
          stop
          if TRAPS[sym] and TRAPS[sym].respond_to?(:call)
            TRAPS[sym].call
          end
        end
      end
    end

    def run(restarted)
      Fiveruns::Dash.logger.info "Starting reporter thread; endpoints are #{update_locations.inspect}"

      install_signals
      error_barrier do
        total_time = 0
        loop do
          # account for the amount of time it took to upload, and adjust the sleep time accordingly
          total_time += time_for { send_info_update }
          rest(@interval - total_time)
          total_time = 0
          total_time += time_for do
            send_data_update
            send_exceptions_update
          end
        end
      end
    end

    def error_barrier
      begin
        yield
      rescue Fiveruns::Dash::ShutdownSignal => me
        return
      rescue Exception => e
        Fiveruns::Dash.logger.error "#{e.class.name}: #{e.message}"
        Fiveruns::Dash.logger.error e.backtrace.join("\n\t")
        retry
      end
    end

    def rest(amount)
      amount > 0 ? sleep(amount) : nil
    end

    def time_for(&block)
      a = Time.now
      block.call
      Time.now - a
    end

    def setup_for(run_in_background = true)
      @background = run_in_background
    end
    
    def send_info_update
      @info_update_sent ||= begin
        payload = InfoPayload.new(@session.info, @started_at)
        Fiveruns::Dash.logger.debug "Sending info: #{payload.to_fjson}"
        result = Update.new(payload).store(*update_locations)
        send_fake_info(payload)
        result
      end
    end
    
    def send_exceptions_update
      if @info_update_sent
        data = @session.exception_data
        if data.empty?
          Fiveruns::Dash.logger.debug "No exceptions for this interval"
        else
          payload = ExceptionsPayload.new(data)
          Fiveruns::Dash.logger.debug "Sending exceptions: #{payload.to_fjson}"
          Update.new(payload).store(*update_locations)
        end        
      else
        # Discard data
        @session.reset
        Fiveruns::Dash.logger.warn "Discarding interval exceptions"
      end
    end
    
    def send_data_update
      if @info_update_sent
        data = @session.data
        payload = DataPayload.new(data)
        Fiveruns::Dash.logger.debug "Sending data: #{payload.to_fjson}"
        result = Update.new(payload).store(*update_locations)
        send_fake_data(payload)
        result
      else
        # Discard data
        @session.reset
        Fiveruns::Dash.logger.warn "Discarding interval data"
      end
    end
    
    def update_locations
      @update_locations ||= if ENV['DASH_UPDATE']
        ENV['DASH_UPDATE'].strip.split(/\s*,\s*/)
      else
        default_update_locations
      end
    end

    def send_fake_data(payload)
      fake_host_count.times do |idx|
        payload.params[:process_id] = Fiveruns::Dash.process_ids[idx+1]
        Fiveruns::Dash.logger.debug "Sending data: #{payload.to_fjson}"
        Update.new(payload).store(*update_locations)
      end
    end

    def send_fake_info(payload)
      host = payload.params[:hostname]
      fake_host_count.times do |idx|
        payload.params[:mac] += idx.to_s
        payload.params[:hostname] = host + idx.to_s
        Fiveruns::Dash.logger.debug "Sending info: #{payload.to_fjson}"
        Update.new(payload).store(*update_locations)
      end
    end

    def fake_host_count
      ENV['DASH_FAKE_HOST_COUNT'].to_i
    end
    
    def default_update_locations
      %w(http://dash-collector.fiveruns.com http://dash-collector02.fiveruns.com)
    end

  end
      
end