class Canvas < Widget
    def initialize(parent, width=0, height=0)
        super(parent)
        
        @session.send_component Canvas,
            File.read('src/wit/canvas/canvas.js')+%{
            function Canvas(mother, id, width, height) {
                var el = mother.document.createElement('div');
                el.style.width = width + 'px';
                el.style.height = height + 'px';
                var self = new Widget(mother, id, el);
                
                self.canvas = new jsGraphics(el);
                
                el.onclick = function (e) {
                    var event = e?e:window.event;
                    var target = event.target?event.target:(event.srcElement?event.srcElement:null);
                    if (!target) return;
                    self.send('click', event.clientX, event.clientY);
                }
                
                return self;
            }
        }
        
        @session.send %Q{
            new Canvas(registry[#{@parent.id}], #{@id}, #{width}, #{height});
        }
    end
    
    def onclick(&block)
        set_event('click', &block)
    end
    
    def setColor(color)
        @session.send %Q{
            registry[#{@id}].canvas.setColor('#{WebApp.escape_string(color)}');
        }
    end
    
    def setStroke(number)
        if number == :DOTTED
            number = 'Stroke.DOTTED'
        end
        
        @session.send %Q{
            registry[#{@id}].canvas.setStroke(#{number});
        }
    end
    
    def drawLine(x1, y1, x2, y2)
        @session.send %Q{
            registry[#{@id}].canvas.drawLine(#{x1}, #{y1}, #{x2}, #{y2});
        }
    end
    
    def drawPolyline(xpoints, ypoints)
        xpoints = xpoints.join(',')
        ypoints = ypoints.join(',')
        @session.send %Q{
            registry[#{@id}].canvas.drawPolyline(new Array(#{xpoints}), new Array(#{ypoints}));
        }
    end
    
    def drawRect(x, y, width, height)
        @session.send %Q{
            registry[#{@id}].canvas.drawRect(#{x}, #{y}, #{width}, #{height});
        }
    end
    
    def fillRect(x, y, width, height)
        @session.send %Q{
            registry[#{@id}].canvas.fillRect(#{x}, #{y}, #{width}, #{height});
        }
    end
    
    def drawPolygon(xpoints, ypoints)
        xpoints = xpoints.join(',')
        ypoints = ypoints.join(',')
        @session.send %Q{
            registry[#{@id}].canvas.drawPolygon(new Array(#{xpoints}), new Array(#{ypoints}));
        }
    end
    
    def drawEllipse(x, y, width, height)
        @session.send %Q{
            registry[#{@id}].canvas.drawEllipse(#{x}, #{y}, #{width}, #{height});
        }
    end
    
    def fillEllipse(x, y, width, height)
        @session.send %Q{
            registry[#{@id}].canvas.fillEllipse(#{x}, #{y}, #{width}, #{height});
        }
    end
    
    def fillArc(x, y, width, height, start_angle, end_angle)
        @session.send %Q{
            registry[#{@id}].canvas.fillArc(#{x}, #{y}, #{width}, #{height}, #{start_angle}, #{end_angle});
        }
    end
    
    def setFont(font_family, size_unit, style)
        if style == :PLAIN
            style = 'Font.PLAIN'
        elsif style == :BOLD
            style = 'Font.BOLD'
        elsif style == :ITALIC
            style = 'Font.ITALIC'
        elsif style == :BOLD_ITALIC or style == :ITALIC_BOLD
            style = 'Font.BOLD_ITALIC'
        else
            style = 'Font.PLAIN'
        end
        
        @session.send %Q{
            registry[#{@id}].canvas.setFont(
                '#{WebApp.escape_string(font_family)}',
                '#{WebApp.escape_string(size_unit)}', #{style});
        }
    end
    
    def drawString(text, x, y)
        @session.send %Q{
            registry[#{@id}].canvas.drawString(
                '#{WebApp.escape_string(text)}', #{x}, #{y});
        }
    end
    
    def drawStringRect(text, x, y, width, alignment)
        if alignment == :LEFT
            alignment = 'left'
        elsif alignment == :CENTER
            alignment = 'center'
        elsif alignment == :RIGHT
            alignment = 'right'
        elsif alignment == :JUSTIFY
            alignment = 'justify'
        else
            alignment = 'left'
        end
        
        @session.send %Q{
            registry[#{@id}].canvas.drawStringRect(
                '#{WebApp.escape_string(text)}', #{x}, #{y}, #{width},
                '#{alignment}');
        }
    end
    
    def drawImage(src, x, y, width, height)
        @session.send %Q{
            registry[#{@id}].canvas.drawImage('#{WebApp.escape_string(src)}',
                #{x}, #{y}, #{width}, #{height});
        }
    end
    
    def paint
        @session.send %Q{
            registry[#{@id}].canvas.paint();
        }
    end
    
    def clear
        @session.send %Q{
            registry[#{@id}].canvas.clear();
        }
    end
    
    def printable=(printable)
        printable_str = 'false'
        if printable
            printable_str = 'true'
        end
        @session.send %Q{
            registry[#{@id}].canvas.setPrintable(#{printable_str});
        }
        printable
    end
end
