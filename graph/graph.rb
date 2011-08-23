# Library for drawing nodes and edges

require 'wit/canvas/doublebuffer'

class Node
    attr_reader :color, :x, :y, :edges
    
    def initialize(color='red', x=100, y=100)
        @graph = nil
        @edges = []
        @color = color
        @x, @y = x, y
        @px, @py = 0, 0
    end
    
    def setGraph(graph)
        @graph = graph
    end
    
    def edgeTo(node)
        @edges << node
    end
    
    def iterate
        friction = 0.95
        repulsion = 200
        attraction = 200
        @px *= friction
        @py *= friction
        
        @graph.nodes.each do |node|
            if node != self
                dist_x = @x - node.x
                dist_y = @y - node.y
                dist_sq = (dist_x * dist_x) + (dist_y * dist_y)
                inv_sq = 1.0 / dist_sq
                inv_sq *= repulsion
                xfact = (1.0 * dist_x) / (dist_x + dist_y)
                yfact = (1.0 * dist_y) / (dist_x + dist_y)
                
                if dist_x > 0
                    @px += inv_sq
                else
                    @px -= inv_sq
                end
                
                if dist_y > 0
                    @py += inv_sq
                else
                    @py -= inv_sq
                end
            end
        end
        
        @edges.each do |node|
            dist_x = @x - node.x
            dist_y = @y - node.y
            dist_sq = (dist_x * dist_x) + (dist_y * dist_y)
            inv_sq = 1.0 / dist_sq
            inv_sq *= attraction
            xfact = (1.0 * dist_x) / (dist_x + dist_y)
            yfact = (1.0 * dist_y) / (dist_x + dist_y)

            if dist_x > 0
                @px -= inv_sq
            else
                @px += inv_sq
            end

            if dist_y > 0
                @py -= inv_sq
            else
                @py += inv_sq
            end
        end
        
        @x += @px
        @y += @py
    end
end

class Graph # acts like a widget
    attr_reader :nodes
    
    def initialize(parent, width=0, height=0)
        @canvas = DoubleBuffer.new(parent, width, height)
        @nodes = []
    end
    
    def addNode(node)
        @nodes << node
        node.setGraph(self)
    end
    
    def iterate
        @nodes.each do |node|
            node.iterate
        end
    end
    
    def paint
        # draw the nodes
        @nodes.each do |node|
            node.edges.each do |edge|
            @canvas.setColor('black')
                @canvas.drawLine(node.x, node.y, edge.x, edge.y)
            end
            
            @canvas.setColor(node.color)
            @canvas.fillEllipse(node.x-10, node.y-10, 20, 20)
        end
        
        @canvas.paint
    end
    
    def method_missing(name, *args)
        @canvas.send(name, *args)
    end
end
