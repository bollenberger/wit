require 'thread'
require 'parsedate'

class Calendar < Widget
    @@calendar_def_mutex = Mutex.new

    def initialize(parent, value='')
        super(parent)
        
        @@calendar_def_mutex.synchronize do
            if @session.app.handlers['resources']['calendar'].nil?
                cal = CompositeHandler.new
                
                cal['calendar.html'] =
                    Response.new(File.open('calendar/calendar.html', 'rb').read)
                cal['cal.gif'] =
                    Response.new(File.open('calendar/cal.gif', 'rb').read, 'image/gif')
                cal['pixel.gif'] =
                    Response.new(File.open('calendar/pixel.gif', 'rb').read, 'image/gif')
                cal['prev.gif'] =
                    Response.new(File.open('calendar/prev.gif', 'rb').read, 'image/gif')
                cal['next.gif'] =
                    Response.new(File.open('calendar/next.gif', 'rb').read, 'image/gif')
                cal['prev_year.gif'] =
                    Response.new(File.open('calendar/prev_year.gif', 'rb').read, 'image/gif')
                cal['next_year.gif'] =
                    Response.new(File.open('calendar/next_year.gif', 'rb').read, 'image/gif')
                
                @session.app.handlers['resources']['calendar'] = cal
            end
        end
        
        @session.send_component Calendar,
            File.read('src/wit/calendar/calendar.js')+%q{
            function Calendar(parent, id, value) {
                var el = parent.document.createElement('span');
                var textbox = parent.document.createElement('input');
                textbox.setAttribute('type', 'text');
                textbox.setAttribute('value', value);
                textbox.setAttribute('readonly', 'readonly');
                var cal = new calendar(textbox);
                var image = parent.document.createElement('img');
                image.setAttribute('src', 'handlers/resources/calendar/cal.gif');
                image.style.height = '16';
                image.style.width = '16';
                image.style.border = '0';
                image.onclick = function () {
                    cal.popup();
                };
                var space = parent.document.createTextNode('\u00A0');
                el.appendChild(textbox);
                el.appendChild(space);
                el.appendChild(image);
                var self = new Widget(parent, id, el);
                
                self.setValue = function (value) {
                    textbox.setAttribute('value', value);
                };
                
                textbox.onchange = function () {
                    self.send('change', textbox.value);
                }
                
                return self;
            }
        }
        
        @session.send %Q{
            new Calendar(registry[#{@parent.id}], #{@id},
                '#{WebApp.escape_string(value)}');
        }
        
        set_event('change') do |value|
            parse_date = ParseDate.parsedate(value.to_s)[0,3]
            
            if parse_date[0].nil?
                @value = nil
            else
                @value = Date.new(*parse_date)
            end
            
            @onchange.call(@value) unless @onchange.nil?
        end
    end
    
    def onchange(&block)
        @onchange = block
    end
    
    def value
        @value
    end
    
    def value=(value)
        if value.kind_of?(Date)
            @value = value
        else
            @value = Date.new(*ParseDate.parsedate(value.to_s)[0,3])
        end
        
        string_value = "#{@value.month}/#{@value.day}/#{@value.year}"
        
        @session.send %Q{
            registry[#{@id}].setValue('#{WebApp.escape_string(string_value)}');
        }
    end
end
