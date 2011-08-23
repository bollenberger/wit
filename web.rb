require 'socket'
require 'timeout'
require 'openssl'

class Request
    attr_accessor :headers, :parameters, :uri

    def initialize
        @headers = {}
        @parameters = {}
        @uri = nil
    end
end

class Response
    attr_accessor :code, :headers, :data
    attr_reader :done

    def initialize(data='', mime='text/html', code=200)
        @code = code
        @headers = {'Content-Type'=>mime}
        @data = data
        @chunked = false
    end
    
    def Response.stream(mime='text/html', code=200)
        response = Response.new('', mime, code)
        response.chunked do
            yield
        end
    end
    
    # Make the response chunked.
    def chunked
        @chunked = true
        @chunked_started = false
        while true
            # If the block returns nil, then this is the last part.
            @data = yield
            break if @data.nil? or data==false or data==''
            
            done = callcc do |continuation|
                @continuation = continuation
                return self
            end
            raise Errno::EPIPE if done
        end
        
        # Return self one last time to terminate the chunking
        @done = true
        self
    end
    
    def send(socket)
        unless @chunked
            @headers['Content-Length'] = @data.length.to_s
        
            socket.write('HTTP/1.1 '+@code.to_s+WebClient::LineBreak)
            @headers.each do |name, value|
                socket.write(name+': '+value+WebClient::LineBreak)
            end
            socket.write(WebClient::LineBreak+@data)
        else
            closed = false
            begin
                unless @chunked_started
                    @chunked_started = true
                    socket.write('HTTP/1.1 '+@code.to_s+WebClient::LineBreak)
                    @headers.each do |name, value|
                        socket.write(name+': '+value+WebClient::LineBreak)
                    end
                    socket.write('Transfer-Encoding: chunked'+
                        WebClient::LineBreak*2)
                end

                if @done
                    socket.write('0'+WebClient::LineBreak+WebClient::LineBreak)
                    return
                end
                
                socket.write(sprintf('%x', @data.length)+
                    WebClient::LineBreak+@data+WebClient::LineBreak)
            rescue Errno::EPIPE, Errno::EINVAL, OpenSSL::SSL::SSLError
                closed = true
            end
                
            # Write out the next chunk
            @continuation.call(closed)
        end
    end
    
    # Allow a Response to act as a static handler.
    def call(request)
        self
    end
end

def hex(digit)
    if digit>='0'[0] and digit<='9'[0]
        digit-'0'[0]
    elsif digit>='A'[0] and digit<='F'[0]
        digit-'A'[0]+10
    elsif digit>='a'[0] and digit<='f'[0]
        digit-'a'[0]+10
    else
        0
    end
end

def urlencode(s)
    encoded = ''
    s.each_byte do |b|
        if (b>='a'[0] and b<='z'[0]) or
            (b>='A'[0] and b<='Z'[0]) or
            (b>='0'[0] and b<='9'[0]) or
            b=='_'[0] or b=='-'[0]
            
            encoded << b
        elsif b==' '[0]
            encoded << '+'
        else
            encoded << "%#{sprintf('%02x', b)}"
        end
    end
    encoded
end

def urldecode(s)
    decoded = ''
    i = 0
    if s.length < 3
        return s
    end
    while i < s.length-2
        if s[i]=='%'[0]
            decoded << hex(s[i+1])*16+hex(s[i+2])
            i += 2
        elsif s[i]=='+'[0]
            decoded << ' '
        else
            decoded << s[i]
        end
        i += 1
    end
    if i < s.length-1
        decoded << s[s.length-2] << s[s.length-1]
    end
    decoded
end

class WebClient
    MaxPost = 0 # max POST data size 0=unlimited
    LineBreak = "\r\n"
    ParameterStart = '?'
    ParameterSeparator = '&'
    ParameterAssign = '='
    StatusCodes = {200=>'OK', 400=>'Bad Request', 404=>'Not Found',
        411=>'Length Required', 413=>'Request Entity Too Large',
        415=>'Unsupported Media Type',
        500=>'Internal Server Error'}

    def initialize(server, socket)
        @server, @socket = server, socket
    end

    def close
	puts "closing " + @socket.to_s
	$stdout.flush
        @socket.close
    end
    
    def send_error(code)
        code = 500 unless StatusCodes.has_key?(code)
        
        response = Response.new
        response.code = code
        response.data = "<!DOCTYPE html\n"+
            "PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"\n"+
            "\"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">\n"+
            "<html><head><title>#{code} #{StatusCodes[code]}</title>\n"+
            "</head><body><h1>#{StatusCodes[code]}</h1></body></html>\n"
        response.send(@socket)
    end
    
    def handle
        keepalive = true
        while keepalive
            method = nil
            version = nil
            request = Request.new
            Timeout::timeout(15) do
                @socket.each(LineBreak) do |line|
                    if method.nil?
                        method, request.uri, version = line.split(' ', 3)
                        request.uri = request.uri.split('/', 2)[1]
                        request.uri = '' if request.uri.nil?
                    else
                        if line==LineBreak
                            break
                        else
                            key, value = line.split(/\: /, 2)
                            key.downcase!
                            request.headers[key] = value[0..-3]
                        end
                    end
                end
            end

            if version.nil?
		keepalive = false
		next
            elsif version!="HTTP/1.1\r\n"
                send_error(400)
                next
            end
            
            if request.headers['connection']=='close'
                keepalive = false
            end

            if method=='GET'
                request.uri, paramstring = request.uri.split(ParameterStart, 2)
                request.uri = '' if request.uri.nil?
                
                unless paramstring.nil?
                    paramstring.split(ParameterSeparator).each do |param|
                        name, value = param.split(ParameterAssign, 2)
                        name = urldecode(name)
                        value = urldecode(value)
                        if name[-2,2]=='[]' # arrays a la PHP
                            name = name[0..-3]
                            if not request.parameters[name].nil? and
                                request.parameters[name].kind_of?(Array)
                                request.parameters[name] << value
                            else
                                request.parameters[name] = [value]
                            end
                        else    
                            request.parameters[name] = value
                        end
                    end
                end
            elsif method=='POST'
                if request.headers['content-length'].nil?
                    send_error(411)
                    next
                end
                
                content_length = request.headers['content-length'].to_i
                if MaxPost!=0 and content_length>MaxPost
                    send_error(413)
                    next
                end
                if request.headers['expect']=='100-continue'
                    @socket.send("HTTP/1.1 100 Continue\r\n\r\n")
                end
                
                content = @socket.read(content_length)
                
                # POST multipart/form-data
                if request.headers['content-type']\
                    .index('multipart/form-data')==0
                    
                    boundary = request.headers['content-type']\
                        .index('boundary=')
                    boundary += 9
                    boundary =
                        '--'+request.headers['content-type'][boundary..-1]
                    
                    content = content.split(boundary)
                    content = content[1..-2]
                    content.each do |part|
                        part_headers = {}
                        part_headers_str, part = part.split(LineBreak*2, 2)
                        part_headers_str =
                            part_headers_str.split(LineBreak)[1..-1]
                        part_headers_str.each do |part_header|
                            part_header_name, part_header_value =
                                part_header.split(': ',2)
                            part_headers[part_header_name.downcase] =
                                part_header_value
                        end
                        name_pos =
                            part_headers['content-disposition']\
                            .index('name="')+6
                        filename = part_headers['content-disposition']\
                            .index('filename="')
                        
                        key = part_headers['content-disposition'][name_pos,
                            part_headers['content-disposition'].index('"',
                            name_pos)-name_pos]
                        part = part[0..-3]
                        unless filename.nil?
                            filename += 10
                            filename = part_headers['content-disposition']\
                                [filename, part_headers['content-disposition']\
                                .index('"', filename)-filename]
                            part = {'filename'=>filename, 'content'=>part,
                                'headers'=>part_headers}
                        end
                        
                        if key[-2..-1]=='[]'
                            key = key[0..-3]
                            if request.parameters.has_key?(key) and
                                request.parameters[key].kind_of?(Array)
                                
                                request.parameters[key] << part
                            else
                                request.parameters[key] = [part]
                            end
                        else
                            request.parameters[key] = part
                        end
                    end
                elsif request.headers['content-type']==
                    'application/x-www-form-urlencoded'
                    
                    content.split(ParameterSeparator).each do |pair|
                        name, value = pair.split(ParameterAssign, 2)
                        name = urldecode(name)
                        value = urldecode(value)
                        
                        if name[-2,2]=='[]' # arrays a la PHP
                            name = name[0..-3]
                            if not request.parameters[name].nil? and
                                request.parameters[name].kind_of?(Array)
                                request.parameters[name] << value
                            else
                                request.parameters[name] = [value]
                            end
                        else    
                            request.parameters[name] = value
                        end
                    end
                end
            else
                send_error(501)
                next
            end
            
            # Handle request
            response = @server.handle(request)
            
            # Send back the response
            if response.nil?
                send_error(404)
            elsif response.kind_of?(Integer)
                send_error(response)
            elsif response.kind_of?(String)
                Response.new(response).send(@socket)
            elsif response.kind_of?(Response)
                response.send(@socket)
            else
                send_error(500)
            end
        end

	close
    end
end

class WebServer
    attr_accessor :handler

    def initialize(port_server=80)
        if port_server.kind_of?(Integer)
            @server = TCPServer.new('0.0.0.0', port_server)
        else
            # Allow the user to specify a server, such as an SSLServer.
            @server = port_server
        end
        @handler = nil
        @thread = nil
    end
    
    def handle(request)
        if @handler.nil?
            nil
        else
            @handler.call(request)
        end
    end
    
    def listen
        @thread = Thread.new do
            while true
                begin
                    t = Thread.new(@server.accept) do |socket|
                        begin
                            WebClient.new(self, socket).handle
                        rescue Errno::EPIPE, Errno::EINVAL, OpenSSL::SSL::SSLError => e
                            # Ignore broken connections. That is how we know that
                            # the client has closed the connection.
                            # Errno::EPIPE is a TCPSocket on UNIX
                            # Errno::EINVAL is a TCPSocket on Windows
                            # OpenSSL::SSL::SSLError is an SSLSocket (tested on Windows)
                            #  OpenSSL is not always present, so we won't check for it, but
                            #  will log it for now. Maybe check to see if the exception
                            #  is defined, and then change behavior?
                        rescue => e
                            # Report any other error
                            puts "Error occurred handling web request: #{e}"
                            puts e.backtrace.join("\n")
                        end
                    end
                    t[:name] = 'WebServer connection handler'
                rescue => e
                    puts "Error accepting a connection: #{e}"
                end
            end
        end
        self
    end

    def join
        @thread.join unless @thread.nil?
    end
end

# Provide a helper for creating an SSL web server.
# Patch a bug in Ruby OpenSSL
# I have been assured by the maintainers that it will be fixed in the next
# release, at which point we can think about removing this.
# In case you are wondering, the problem was that the line below read:
# while line = self.gets(eol?)
module Buffering
  def each(eol=$/)
    while line = self.gets(eol)
      yield line
    end
  end
  alias each_line each
end

include OpenSSL

class SSLWebServer < WebServer
    def initialize(cert, key, port_server=443)
        tcp = nil
        if port_server.kind_of?(Integer)
            tcp = TCPServer.new('0.0.0.0', port_server)
        else
            # Allow the user to specify another server object.
            tcp = port_server
        end
        ctx = SSL::SSLContext.new
        ctx.cert = X509::Certificate.new(File.read(cert))
        ctx.key = PKey::RSA.new(File.read(key))
        ssl = SSL::SSLServer.new(tcp, ctx)
        super(ssl)
    end
end

# Required the UNIX "file" utility if the file type is not listed in MimeTypes.
class FileSystemHandler
    MimeTypes = {
        ".html" => "text/html",
        ".htm" => "text/html",
        ".css" => "text/css"
    }
    
    Index = [
        "index.html", "index.htm"
    ]

    def initialize(path)
        @path = File.expand_path(path)
    end
    
    def call(request)
        # Cleanse the URI. TODO make sure this is actually secure.
        # It's probably not.
        if /\.\./ =~ request.uri or
            /\$/ =~ request.uri or
            /~/ =~ request.uri
            puts "Insecure string: #{request.uri}"
            return nil
        end
        
        puts "Request: #{request.uri}"
        
        result = call_with_index(request, '')
        return result unless result.nil?
        
        # Try adding a slash and then try the indices
        if request.uri[-1,1] != '/'
            request.uri += '/'
        end
        
        result = nil
        Index.each do |index|
            result = call_with_index(request, index)
            break unless result.nil?
        end
        result
    end
    
private

    def mimetype(filename)
        MimeTypes.each_pair do |extension, type|
            if filename[-extension.length..-1] == extension
                return type
            end
        end
        %x{file -ib #{filename}}.chomp        
    end
    
    def call_with_index(request, index)
        filename = @path+'/'+request.uri + index
        
        begin
            Response.new(File.open(filename, "rb").readlines.join,
                mimetype(filename))
        rescue
            # If something bad happens accessing the file, just return nil
            # (file not found)
            nil
        end
    end
end

require 'erb'
class FileSystemTemplateHandler < FileSystemHandler
    def call(request)
        response = super.call(request)
        
        # Check if the content is text and run it as a template if so.
        if not response.nil? and response.headers['Content-Type'][0,5]=='text/'
            response.data = ERB.new(response.data).result(binding)
        end
        
        response
    end
end

class SiteTemplateHandler < FileSystemHandler
    def initialize(template, path)
        super(path)
        
        @template = template
    end

    # Place all html files into the site template.
    def call(request)
        response = super(request)
        
        if not response.nil? and response.headers['Content-Type']=='text/html'
            response.data = ERB.new(response.data +
                File.open(@template, "rb").readlines.join).result(binding)
        end
        
        response
    end
end

class HostHandler
    attr_accessor :hosts

    def initialize(hosts={})
        @hosts = hosts
    end
    
    def call(request)
        host = request.headers['host']
        
        unless @hosts.has_key?(host)
            nil
        else
            @hosts[host].call(request)
        end
    end
end

class CompositeHandler
    def initialize(handlers={})
        @handlers = handlers
    end
    
    def []=(name, handler)
        @handlers[name] = handler
    end
    
    def [](name)
        @handlers[name]
    end
    
    def call(request)
        uri = request.uri
        directory, request.uri = request.uri.split('/', 2)
        request.uri = '' if request.uri.nil?
        directory = '' if directory.nil?
        
        unless @handlers.has_key?(directory)
            if @handlers.has_key?('')
                request.uri = uri
                @handlers[''].call(request)
            else
                nil
            end
        else
            @handlers[directory].call(request)
        end
    end
end
