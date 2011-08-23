require 'thread'
require 'wit/web'
require 'wit/widgets'

class Session
    attr_reader :sid, :app

    def initialize(app, referer)
        @mutex = Mutex.new
        @send = []
        @send_cv = ConditionVariable.new
        
        @app = app
        @sid = @app.next_id
        @referer = referer
        @finished = false
        @threads = []
        @threads_mutex = Mutex.new
        
        @widgets = {}
        @widget_id = 0
        @widget_mutex = Mutex.new
        
        # Track client side components that have been sent.
        @components = {}
    end
    
    def referer
        referer = @referer
        referer += '/' unless referer[-1]=='/'[0]
        referer
    end
    
    def get_sent_message
        message = ''
        @mutex.synchronize do
            while @send.empty?
                @send_cv.wait(@mutex)
            end
            
            # Allow globbing messages together
            until @send.empty?
                message += @send.shift
            end
            
            @send_cv.signal
        end
        message
    end
    
    # Send a javascript message to the client
    def send(message)
        send_raw "<script language='javascript' type='text/javascript'>"+
            "#{message}</script>"
    end
    
    # Send a component, but only once per session for each component type.
    def send_component(klass, message, &block)
        unless @components.has_key?(klass)
            @components[klass] = true
            send(message)
            
            block.call unless block.nil?
        end
    end
    
    # Send a message to the client without the javascript tags around it.
    def send_raw(message)
        raise "Session finished" if @finished
        @mutex.synchronize do
            @send << message
            @send_cv.signal
        end
    end
    
    def receive(id, event, args)
        return if @finished
        
        @widgets[id.to_i].event(event, *args)
    end
    
    def server_widget(id)
        return nil if @finished
        
        widget = @widgets[id.to_i]
        
        return nil if widget.nil? or not widget.respond_to?(:serve)
        
        widget.serve
    end
    
    def new_thread(*args, &block)
        t = nil
        @threads_mutex.synchronize do
            return nil if @finished
            t = Thread.new(*args, &block)
            @threads << t
        end
        t
    end
    
    def finish
        @threads_mutex.synchronize do
            @finished = true
            @threads.each do |thread|
                thread.kill
            end
        end
    end
    
    def register_widget(widget)
        @widget_mutex.synchronize do
            id = @widget_id
            @widgets[id] = widget
            @widget_id += 1
            id
        end
    end
    
    # Return false if the widget id was not found.
    def unregister_widget(widget)
        not @widgets.delete(widget.id).nil?
    end
end

class WebApp
    attr_reader :handlers

    def initialize(title='WebApp', icon=nil, &main)
        @sessions = {}
        @next_id = 0
        @title = title
        
        # Create a default sub handler namespace:
        #
        # handlers          The application may register other names under
        #   |               handlers.
        #   |
        #   \-resources     Widget types should register their supporting
        #                   files under subdirectories of resources.
        @handlers = CompositeHandler.new
        @handlers['resources'] = CompositeHandler.new
        
        unless icon.nil?
            File.new(icon, 'rb') do |f|
                @icon = Response.new(f.read, 'image/ico')
            end
        end
        
        @main = main
    end

    # Either provide a block to the constructor or override main to
    # provide the application entry point.
    def main(window)
        @main.call(window) unless @main.nil?
    end
    
    def WebApp.escape_string(s)
        encoded = ''
        s.each_byte do |b|
            if (b>='a'[0] and b<='z'[0]) or
                (b>='A'[0] and b<='Z'[0]) or
                (b>='0'[0] and b<='9'[0]) or
                b=='_'[0] or b=='-'[0] or b==' '[0]
                
                encoded << b
            else
                encoded << '\\' + "x#{sprintf('%02x', b)}"
            end
        end
        encoded
    end
    
    def WebApp.random_string(length)
        rand_string = ''
        1.upto(length) do
            rand_string << rand('z'[0]-'a'[0])+'a'[0] # lower case letters
        end
        rand_string
    end
    
    def next_id
        # Make this unique and probabilistically difficult to guess
        @next_id += 1
        WebApp.random_string(20)+@next_id.to_s
    end
    
    def call(request)
        puts "Request: #{request.uri}"
        if request.uri==''
            # Main frameset page
            session = Session.new(self, request.headers['referer'])
            puts "New session id=#{session.sid}"
            @sessions[session.sid] = session
            
            %Q{<?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html PUBLIC
            "-//W3C//DTD XHTML 1.0 Frameset//EN"
            "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">
            <html><head><title>#{@title}</title>
            <meta http-equiv='Pragma' content='no-cache' />
            </head>
            <frameset border='0' cols='*,0,0'>
                <frame src='display?sid=#{session.sid}' name='display' border='0'/>
                <frame src='javascript:false;' name='receive' border='0' scrolling='no'/>
                <frame src='javascript:false;' name='send' border='0' scrolling='no'/>
            </frameset>
            </html>}
        elsif request.uri=='display'
            %Q{<?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
            "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
            <html><head><title></title></head><body>
            <script language='javascript' type='text/javascript'>
            parent.frames['receive'].location.href = 'receive?sid=#{request.parameters['sid']}';
            </script>
            </body></html>}
        elsif request.uri=='receive'
            # Javascript streaming page
            first = true
            response = nil
            
            session = @sessions[request.parameters['sid']]
            if session.nil?
                Response.new('', 'text/html', 500)
            else
                # Asynchronously start the application on this session
                main_thread = session.new_thread do
                    begin
                        main(RootWidget.new(session))
                    rescue => e
                        puts "Error occurred in application thread: #{e}"
                        puts e.backtrace.join("\n")
                    end
                end
                main_thread[:name] = session.sid + '_main_thread'
                
                # Ping the client periodically
                ping_thread = session.new_thread do
                    begin
                        while true
                            sleep 10
                            session.send('')
                        end
                    rescue
                        # Ignore error and quit thread.
                        # This means that the connection was closed, so we want
                        # to close this thread anyway.
                    end
                end
                ping_thread[:name] = session.sid + '_ping_thread'
                
                begin
                    response = Response.stream do
                        if first
                            first = false
                            %Q{<html>
                            <head><title></title>
                            <meta http-equiv='Pragma' content='no-cache' />
                            </head><body>}
                        else
                            message = session.get_sent_message
                            #puts "Message: #{message.to_s}"
                            message
                        end
                    end
                rescue Errno::EPIPE => e
                    puts "Ending session by client "+session.sid.to_s
                    session.finish
                    @sessions.delete(request.parameters['sid'])
                    return nil
                rescue => e
                    puts e
                end
                if response.done
                    puts "Ending session by server "+sid.to_s
                    session.finish
                    @sessions.delete(request.parameters['sid'])
                end
                response
            end
        elsif request.uri=='send'
            # Client responses come in via requests to this page
            Thread.new do
                unless @sessions[request.parameters['sid']].nil?
                    begin
                        @sessions[request.parameters['sid']].receive(
                            request.parameters['id'],
                            request.parameters['event'],
                            request.parameters['args'])
                    rescue => e
                        # Report any error
                        puts "Error in send: #{e}"
                        puts e.backtrace.join("\n")
                    end
                end
            end
            
            # Send blank HTML
            %q{<?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
            "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
            <html><head><title></title></head><body></body></html>}
        
        elsif request.uri=='widget'
            session = @sessions[request.parameters['sid']]
            session.server_widget(request.parameters['id'])
        elsif request.uri[0,9]=='handlers/'
            request.uri = request.uri[9..-1]
            @handlers.call(request)
        elsif request.uri=='favicon.ico'
            @icon
        else
            nil
        end
    end
end
