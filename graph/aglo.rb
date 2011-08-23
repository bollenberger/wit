require 'wit/canvas/doublebuffer'

class Point
    attr_reader :x, :y
    
    def initialize(x=0, y=0)
        @x, @y = x, y
    end
    
    def add(point)
        @x += point.x
        @y += point.y
        self
    end
    
    def subtract(point)
        @x -= point.x
        @y -= point.y
        self
    end
    
    def multiply(number)
        @x *= number
        @y *= number
        self
    end
    
    def zero
        @x = 0
        @y = 0
        self
    end
    
    def norm
        Math.sqrt(@x*@x + @y*@y)
    end
end

class Vector
    attr_reader :points
    
    def initialize(graph)
        ary = graph.nodes.size
        
        @points = []
        ary.times do 
            @points << Point.new
        end
    end
    
    def add(vector)
        @points.each_index do |i|
            @points[i].add(vector.points[i])
        end
        self
    end
    
    def multiply(number)
        @points.each do |point|
            point.multiply(number)
        end
        self
    end
    
    def zero
        @points.each do |point|
            point.zero
        end
        self
    end
    
    def norm
        n = 0
        @points.each do |point|
            pn = point.norm
            n += pn * pn
        end
        Math.sqrt(n)
    end
end

class Node
    attr_reader :point, :color, :edges_to
    
    def initialize(color = 'black', x = 0.0, y = 0.0)
        @color = color
        @point = Point.new(x, y)
        @graph = nil
        @edges_to = []
    end
    
    def set_graph(graph)
        @graph = graph
    end
    
    def add_edge_to(to_node)
        @graph.edges[self] << to_node
        to_node.edges_to << self
    end
    
    def connected?
        if @graph.edges[self].length > 0
            true
        elsif @edges_to.length > 0
            true
        else
            false
        end
    end
end

class Aesthetic
    def initialize(weight = 1.0)
        @weight = weight
    end
    
    def find_gradient(graph)
        gradient(graph).multiply(@weight)
    end
    
    def gradient(graph)
        nil # override in your concrete subclass
    end
end


module Centroid
    def get_centroid(graph)
        update = false
        if @cached_centroid.nil?
            @cached_centroid = Point.new
            update = true
        elsif graph.sequence > @sequence
            update = true
        end
        @sequence = graph.sequence
        
        if update
            count = 0
            @cached_centroid.zero
            graph.nodes.each do |node|
                @cached_centroid.add(node.point)
                count += 1
            end
            @cached_centroid.multiply(1.0 / count)
        end
        
        @cached_centroid
    end
end

class Centripetal < Aesthetic
    include Centroid
    
    def gradient(graph)
        gradient = Vector.new(graph)
        
        centroid = get_centroid(graph)
        
        graph.nodes.each_index do |i|
            node = graph.nodes[i]
            
            if node.connected?
            
                delta = node.point.dup.subtract(centroid)
                norm = delta.norm
                if norm < 1e-8
                    norm = 1e-8
                end
                
                delta.multiply(1.0 / norm)
                
                gradient.points[i].add(delta)
            else
                node.point.zero
                gradient.points[i].zero
            end
        end
        
        gradient
    end
end

class Graph
    attr_reader :nodes, :edges, :sequence
    
    def initialize(parent, width=0, height=0)
        @canvas = DoubleBuffer.new(parent, width, height)
        
        @nodes = []
        @edges = {}
        @edges.default = []
        
        @sequence = 0
    end
    
    def paint
        # draw the nodes
        @nodes.each do |node|
            @edges[node].each do |edge|
                @canvas.setColor('black')
                @canvas.drawLine(node.point.x, node.point.y, edge.point.x, edge.point.y)
            end
            
            @canvas.setColor(node.color)
            @canvas.fillEllipse(node.point.x-10, node.point.y-10, 20, 20)
        end
        
        @canvas.paint
    end
    
    def animate_layout
        aglo([Centripetal.new]) do
            paint
        end
    end
    
    def method_missing(name, *args)
        @canvas.send(name, *args)
    end
    
    def aglo(aesthetics, iterations=100, beginning_temp=100.0, ending_temp=0.001, &block)
        temp = beginning_temp
        cooling = (beginning_temp / ending_temp) ** (1.0 / iterations)
        gradient = Vector.new(self)
        iterations.times do
            gradient.zero
            aesthetics.each do |aesthetic|
                gradient.add(aesthetic.find_gradient(self))
            end
            norm = gradient.norm
            if norm > temp
                gradient.multiply(temp / norm)
            end
            
            add_vector(gradient)
            
            temp = temp / cooling
            
            @sequence += 1
            
            # A little per-iteration callback
            unless block.nil?
                block.call
            end
        end
    end
    
    def add_vector(vector)
        @nodes.each_index do |i|
            @nodes[i].point.add(vector.points[i])
        end
    end
    
    def add_node(node)
        @nodes << node
        node.set_graph(self)
    end
end
