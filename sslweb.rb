require 'web.rb'
require 'openssl'

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
