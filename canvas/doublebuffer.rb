# A helper to automatically manage a double buffering pair of canvases.

require 'wit/canvas/canvas'

class DoubleBufferStyle
    def initialize(widget)
        @widget = widget
    end
    
    def method_missing(name, *args)
        @widget.canvases.each do |canvas|
            canvas.style.send(name, *args)
        end
    end
end

class DoubleBuffer # acts like a widget
    attr_reader :canvases, :style
    
    def initialize(parent, width=0, height=0)
        @canvases = [Canvas.new(parent, width, height),
            Canvas.new(parent, width, height)]
        
        @style = DoubleBufferStyle.new(self)
    end
    
    def paint
        front = @canvases[0]
        back = @canvases[1]
        
        back.paint
        front.clear
        @canvases.reverse!
    end
    
    def clear
        front = @canvases[0]
        front.clear
    end
    
    def onclick(&block)
        @canvases.each do |canvas|
            canvas.onclick(&block)
        end
    end
    
    def method_missing(name, *args)
        back = @canvases[1]
        back.send(name, *args)
    end
end
