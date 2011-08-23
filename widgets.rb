require 'thread'

# Support setting arbitrary styles on widgets like:
# widget.style.display = 'inline'
class Style
    def initialize(widget)
        @widget = widget
    end
    
    def method_missing(name, *args)
        name = name.to_s
        if name[-1]=='='[0]
            name, value = name[0..-2], args[0].to_s
            @widget.session.send %Q{
                registry[#{@widget.id}].element.style.#{name} =\
                '#{WebApp.escape_string(value)}';
            }
        else
            nil
        end
    end
end

class Widget
    attr_reader :id, :session, :style, :parent

    def initialize(parent)
        if parent.kind_of?(Widget)
            @session = parent.session
            @parent = parent
            @id = @session.register_widget(self)
            @parent.add_child(self)
        elsif parent.kind_of?(Session)
            @session = parent
            @parent = nil
            @id = @session.register_widget(self)
        else
            raise "Invalid parent"
        end
        
        @style = Style.new(self)
        @children = {}
        @events = {}
        
        @session.send_component(Widget, %Q{
            var sendFrame = parent.frames['send'];
            var displayFrame = parent.frames['display'];
            var baseURI = parent.location.href;
            var registry = [];
            
            function Widget(mother, id, element) {
                // ** Constructor **
                
                registry[id] = this;
                this.id = id;
                
                this.parent = mother;
                
                this.element = element;
            
                // In objects with an internal frame and an external frame,
                // the containerElement is the internal frame.
                this.containerElement = element;
                this.children = [];
            
                this.parent.addChild(this);
            
                this.window = mother.window;
                this.document = mother.document;
                
                this.eventMask = [];
                
                // ** Methods **
                
                this.send = function (event) {
                    /*if (this.eventMask[event]) {
                        var uri=baseURI+'send?sid=#{@session.sid}&id='+this.id+
                            '&event='+event;
                        for (i=1;i<this.send.arguments.length;++i) {
                            uri += '&args[]='+encodeURI(this.send.arguments[i]);
                        }
                        sendFrame.location.href=uri;
                    }GET*/
                    if (!this.eventMask[event]) return false;
                    
                    var d = sendFrame.document;
                    var b = d.body;
                    var f = d.createElement('form');
                    f.setAttribute('method', 'post');
                    f.setAttribute('action', baseURI+'send');
                    b.appendChild(f);
                    var sid = d.createElement('input');
                    sid.setAttribute('name', 'sid');
                    sid.setAttribute('value', '#{@session.sid}');
                    f.appendChild(sid);
                    var id = d.createElement('input');
                    id.setAttribute('name', 'id');
                    id.setAttribute('value', this.id);
                    f.appendChild(id);
                    var event_el = d.createElement('input');
                    event_el.setAttribute('name', 'event');
                    event_el.setAttribute('value', event);
                    f.appendChild(event_el);
                    
                    for (i=1;i<this.send.arguments.length;++i) {
                        var arg = d.createElement('input');
                        arg.setAttribute('name', 'args[]');
                        arg.setAttribute('value', this.send.arguments[i]);
                        f.appendChild(arg);
                    }
                    
                    f.submit();
                    
                    return true;
                };
                
                this.addChild = function (child) {
                    this.children[child.id] = child;
                    if (child.element != null) {
                        this.containerElement.appendChild(child.element);
                    }
                };
            
                this.removeChild = function (child) {
                    delete this.children[child.id];
                    if (child.element != null) {
                        this.containerElement.removeChild(child.element);
                    }
                };
                
                this.moveBefore = function (sibling) {
                    this.parent.containerElement.removeChild(this.element);
                    this.parent.containerElement.insertBefore(this.element,
                        sibling.element);
                };
            
                this.destroy = function () {
                    // Destroy all sub children recursively.
                    for (var child_id in this.children) {
                        this.children[child_id].destroy();
                    }
                    
                    // Call any other destruction operations on this object.
                    if (this.remove!=null) {
                        this.remove();
                    }
            
                    // Destroy this widget.
                    delete registry[this.id];
                    this.parent.removeChild(this);
                };
            }
        })
    end
    
    def destroy
        # Destroy the widget on the client
        @session.send "registry[#{@id}].destroy();"
        
        # Destroy all children recursively
        @children.each_value do |child|
            child.destroy
        end
        
        # Destroy this widget
        @session.unregister_widget(self)
        @parent.remove_child(self)
    end
    
    def move_before(sibling)
        # Check that sibling is really a sibling (share a parent)
        if sibling.parent != @parent
            raise "Cannot move before a non-sibling."
        end
        @session.send "registry[#{@id}].moveBefore(registry[#{sibling.id}]);"
    end
    
    # Display an alert box, from any widget
    def alert(text)
        @session.send %Q{alert('#{WebApp.escape_string(text.to_s)}');}
    end
    
    # Display a confirm box, from any widget, and get the result (true or false)
    def confirm(prompt)
        mutex = Mutex.new
        response = nil
        got_response = ConditionVariable.new
        
        set_event('confirm') do |value|
            mutex.synchronize do
                response = value=='true' ? true : false
                set_event('confirm')
                got_response.signal
            end
        end
        
        mutex.synchronize do
            @session.send %Q{registry[#{@id}].send('confirm', confirm('#{WebApp.escape_string(prompt.to_s)}'));}
            while response.nil?
                got_response.wait(mutex)
            end
            got_response.signal
        end
        
        response
    end
    
    # Display a prompot box, from any widget, and get the result string.
    def prompt(prompt, default='')
        mutex = Mutex.new
        response = nil
        got_response = ConditionVariable.new
        
        set_event('prompt') do |value|
            mutex.synchronize do
                response = value
                set_event('prompt')
                got_response.signal
            end
        end
        
        mutex.synchronize do
            @session.send %Q{
                value = prompt('#{WebApp.escape_string(prompt.to_s)}',
                    '#{WebApp.escape_string(default.to_s)}');
                if (value == null) {
                    value = '';
                }
                registry[#{@id}].send('prompt', value);
            }
            while response.nil?
                got_response.wait(mutex)
            end
            got_response.signal
        end
        
        response
    end
    
    # Call an event handler
    def event(name, *args)
        if @events.has_key?(name) and not @events[name].nil?
            @events[name].call(*args)
        end
    end
    
    # Setup an event handler
    def set_event(name, &block)
        if @events[name].nil? != block.nil?
            @events[name] = block
            @session.send %Q{registry[#{@id}].
                eventMask['#{WebApp.escape_string(name)}'] =
                #{(block.nil?)?'false':'true'};}
        end
    end
    
    # Do not call add and remove child. Create widgets with the
    # constructor and destroy them with destroy.
    def add_child(child)
        @children[child.id] = child
    end
    
    def remove_child(child)
        @children.delete(child.id)
    end
end

# The special root window widget. Automatically created for an application.
class RootWidget < Widget
    def initialize(session)
        super(session)
        
        @session.send %Q{
            var dummyParent = new Object();
            dummyParent.window = displayFrame;
            dummyParent.document = displayFrame.document;
            dummyParent.parent = null;
            dummyParent.addChild = function (child) {};
            dummyParent.removeChild = function (child) {};
            new Widget(dummyParent, #{@id}, displayFrame.document.documentElement.getElementsByTagName("body")[0]);
        }
    end
end


# Does not work on Opera, even Opera 8 Beta since
# window.open().document.body == null
# Bug reported to Opera.
class Window < Widget
    def initialize(parent, caption)
        super(parent)
        
        @session.send_component(Window, %q{
            function Window(mother, id, title) {
                var self = new Widget(mother, id, null);
                self.window = mother.window.open('', '_blank',
                'menubar=no,location=no,status=no,toolbar=no,resizable=yes');
                self.document = self.window.document;
                self.containerElement = self.document.body;
                self.document.title = title;
                return self;
            }
        })
        
        @session.send %Q{
            new Window(registry[#{parent.id}], @id,
                '#{WebApp.escape_string(caption)}');
        }
    end
end

# A simple command button.
class Button < Widget
    def initialize(parent, caption)
        super(parent)
        
        @caption = caption
        
        @session.send_component(Button, %q{
            function Button(mother, id, caption) {
                var el = mother.document.createElement('input');
                el.setAttribute('type', 'button');
                el.setAttribute('value', caption);
                var self = new Widget(mother, id, el);
                
                self.setCaption = function(caption) {
                    self.element.setAttribute('value', caption);
                };
                
                el.onclick = function () {
                    self.send('click');
                };
                
                return self;
            }
        })
        
        @session.send %Q{
            new Button(registry[#{parent.id}], #{@id},
                '#{WebApp.escape_string(caption)}');
        }
    end
    
    def onclick(&block)
        set_event('click', &block)
    end
    
    def caption
        @caption
    end
    
    def caption=(caption)
        return @caption if @caption==caption
        @session.send %Q{registry[#{@id}].setCaption(
            '#{WebApp.escape_string(caption)}');}
        @caption = caption
    end
end

class TextBox < Widget
    def initialize(parent, value='', password=false)
        super(parent)
        
        @value = value
        
        @session.send_component(TextBox, %q{
            function TextBox(mother, id, value, password) {
                var el = mother.document.createElement('input');
                var type = password?'password':'text';
                el.setAttribute('type', type);
                el.setAttribute('value', value);
                var self = new Widget(mother, id, el);
                
                self.setValue = function (value) {
                    self.element.setAttribute('value', value);
                };
                
                el.onchange = function () {
                    self.send('change', self.element.value);
                }
                
                return self;
            }
        })
        
        @session.send %Q{
            new TextBox(registry[#{@parent.id}], #{@id},
                '#{WebApp.escape_string(@value)}',
                #{(password)?'true':'false'});
        }
        
        set_event('change') do |new_value|
            @value = new_value
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
        return @value if @value==value
        @session.send %Q{registry[#{@id}].setValue(
            '#{WebApp.escape_string(value)}');}
        @value = value
    end
end

class TextArea < Widget
    def initialize(parent, value='', rows=5, cols=30)
        super(parent)
        
        @value = value
        @rows, @cols = rows, cols
        
        @session.send_component(TextArea, %q{
            function TextArea(mother, id, value, rows, cols) {
                var el = mother.document.createElement('textarea');
                el.value = value;
                el.setAttribute('rows', rows);
                el.setAttribute('cols', cols);
                var self = new Widget(mother, id, el);
                
                self.setValue = function (value) {
                    self.element.value = value;
                };
                
                self.setRows = function (rows) {
                    self.element.setAttribute('rows', rows);
                }
                
                self.setCols = function (cols) {
                    self.element.setAttribute('cols', cols);
                }
                
                el.onchange = function () {
                    self.send('change', self.element.value);
                }
                
                return self;
            }
        })
        
        @session.send %Q{
            new TextArea(registry[#{@parent.id}], #{@id},
                '#{WebApp.escape_string(@value)}',
                #{rows.to_i.to_s}, #{cols.to_i.to_s});
        }
        
        set_event('change') do |new_value|
            @value = new_value
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
        return @value if @value==value
        @session.send %Q{registry[#{@id}].setValue(
            '#{WebApp.escape_string(value)}');}
        @value = value
    end
    
    def rows
        @rows
    end
    
    def cols
        @cols
    end
    
    def rows=(rows)
        if rows!=@rows
            @session.send %Q{registry[#{@id}].setRows(#{rows.to_i.to_s});}
            @rows = rows
        end
    end
    
    def cols=(cols)
        if cols!=@cols
            @session.send %Q{registry[#{@id}].setCols(#{rows.to_i.to_s});}
            @cols = cols
        end
    end
end

# A select box, which should contain some options
class Select < Widget
    def initialize(parent, multiple=false)
        super(parent)
                
        @session.send_component(Select, %q{
            function Select(mother, id, multiple) {
                var el = mother.document.createElement('select');
                var self = new Widget(mother, id, el);
                if (multiple) {
                    el.focus(); // Work around IE.
                    el.multiple = true;
                }
                
                self.select = function (index) {
                    self.element.options[index].selected = true;
                };
                
                self.deselect = function (index) {
                    self.element.options[index].selected = false;
                };
                
                self.setSize = function (size) {
                    if (multiple) {
                        el.size = size;
                    }
                };
                
                el.onchange = function () {
                    if (multiple) {
                        var selected = '';
                        var selected_index = [];
                        while (self.element.selectedIndex != -1) {
                            selected += self.element.options[self.element.selectedIndex].value+',';
                            selected_index.push(self.element.selectedIndex);
                            self.element.options[self.element.selectedIndex].selected = false;
                        }
                        for (var i=0;i<selected_index.length;++i) {
                            self.element.options[selected_index[i]].selected = true;
                        }
                        
                        self.send('change', selected);
                    } else {
                        self.send('change', self.element.value);
                    }
                }
                
                return self;
            }
        })
        
        if multiple
            @value = []
            @size = 5
        else
            @value = nil
            @size = 0
        end
        
        @session.send %Q{
            new Select(registry[#{@parent.id}], #{@id},
                #{(multiple)?('true'):('false')});
        }
        
        set_event('change') do |ids|
            @value = ids.split(',').collect do |id|
                @children[id.to_i].object
            end
            @value = @value[0] unless multiple
            
            @onchange.call(@value) unless @onchange.nil?
        end
    end
    
    def onchange(&block)
        @onchange = block
    end
    
    def size=(size)
        @session.send(%Q{
            registry[#{@id}].setSize(#{size.to_i});
        })
    end
    
    def multiple?
        multiple
    end
    
    attr_reader :value, :size
end

class Option < Widget
    def initialize(parent, object, label=nil)
        raise "Parent must be a Select" unless parent.kind_of?(Select)
        
        super(parent)
        
        @object = object
        label = @object.to_s if label.nil?
        
        @session.send_component(Option, %q{
            function Option(mother, id, label) {
                var el = mother.document.createElement('option');
                el.setAttribute('value', id);
                var self = new Widget(mother, id, el);
                self.label = mother.document.createTextNode(label);
                el.appendChild(self.label);
                
                self.setLabel = function (label) {
                    self.label.data = label;
                }
                
                return self;
            }
        })
        
        @session.send(%Q{
            new Option(registry[#{@parent.id}], #{@id},
                '#{WebApp.escape_string(label)}');
        })
    end
    
    def label=(label)
        label = label.to_s
        if label != @label
            @label = label
            @session.send(%Q{
                registry[#{@id}].setLabel('#{WebServer.escape_string(label)}');
            })
        end
    end
    
    attr_reader :object
end

class CheckBox < Widget
    def initialize(parent, checked=false)
        super(parent)
        
        @checked = checked
        
        @session.send_component(CheckBox, %q{
            function CheckBox(mother, id, checked) {
                var el = mother.document.createElement('input');
                el.setAttribute('type', 'checkbox');
                el.checked = checked;
                var self = new Widget(mother, id, el);
                
                el.onclick = function () {
                    self.send('click', self.element.checked);
                    return false;
                }
                
                return self;
            }
        })
        
        @session.send(%Q{
            new CheckBox(registry[#{@parent.id}], #{@id}, #{checked});
        })
        
        set_event('click') do |checked|
            if checked == 'true'
                checked = true
            else
                checked = false
            end
            
            mark = true
            unless @onclick.nil?
                mark = @onclick.call(checked)
            end
            
            if mark
                self.checked = checked
            end
        end
    end
    
    def onclick(&block)
        @onclick = block
    end
    
    def toggle
        self.checked = !@checked
    end
    
    def checked
        @checked
    end
    
    def checked=(checked)
        if checked != @checked
            if checked
                checked = true
            else
                checked = false
            end
            
            @session.send(%Q{
                registry[#{@id}].element.checked = #{checked};
            })
            @checked = checked
        end
        
        @checked
    end
end

class Label < Widget
    def initialize(parent, text)
        super(parent)
        
        @text = text
        
        @session.send_component(Label, %q{
            function Label(mother, id, text) {
                var text = mother.document.createTextNode(text);
                var el = mother.document.createElement('span');
                el.appendChild(text);
                var self = new Widget(mother, id, el);
                
                el.onclick = function () {
                    self.send('click');
                }
                
                return self;
            }
        })
        
        @session.send(%Q{
            new Label(registry[#{@parent.id}], #{@id}, '#{WebApp.escape_string(text)}');
        })
    end
    
    def onclick(&block)
        set_event('click', &block)
    end
    
    def text
        @text
    end
    
    def text=(text)
        if @text != text
            @session.send %Q{
                registry[#{@id}].element.firstChild.nodeValue =
                    '#{WebApp.escape_string(text)}';
            }
            @text = text
        end
        @text
    end
end

class Link < Widget
    def initialize(parent, text, url=nil, target=nil)
        super(parent)
        
        @text = text
        @url = url
        @target = target
        
        @session.send_component(Link, %q{
            function Link(mother, id, text, url, target) {
                var text = mother.document.createTextNode(text);
                var el = mother.document.createElement('a');
                el.setAttribute('href', url);
                el.setAttribute('target', target);
                el.appendChild(text);
                var self = new Widget(mother, id, el);
                
                el.onclick = function () {
                    return !self.send('click');
                }
                
                return self;
            }
        })
        
        if url.nil?
            url = '#'
        end
        
        if target.nil?
            target = 'null'
        else
            target = "'#{WebApp.escape_string(target)}'"
        end
        
        @session.send(%Q{
            new Link(registry[#{@parent.id}], #{@id},
                '#{WebApp.escape_string(text)}',
                '#{WebApp.escape_string(url)}',
                #{target});
        })
    end
    
    def onclick(&block)
        if not block.nil?
            url = nil
        end
        set_event('click', &block)
    end
    
    def text
        @text
    end
    
    def text=(text)
        if @text != text
            @session.send %Q{
                registry[#{@id}].element.firstChild.nodeValue =
                    '#{WebApp.escape_string(text)}';
            }
            @text = text
        end
        @text
    end
    
    def url
        @url
    end
    
    def url=(url)
        if url.nil?
            url = '#'
        else
            onclick
        end
        if @url != url
            @session.send %Q{
                registry[#{@id}].element.setAttribute('href',
                    '#{WebApp.escape_string(url)}');
            }
            @url = url
        end
        @url
    end
    
    def target
        @target
    end
    
    def target=(target)
        if @target != target
            @target = target
            
            if target.nil?
                target = 'null'
            else
                target = "'#{WebApp.escape_string(target)}'"
            end
            
            @session.send %Q{
                registry[#{@id}].element.setAttribute('target', #{target});
            }
        end
        
        @target
    end
end

class Table < Widget
    def initialize(parent)
        super(parent)
        
        @session.send_component(Table, %q{
            function Table(mother, id) {
                var el = mother.document.createElement('table');
                var self = new Widget(mother, id, el);
                return self;
            }
        })
        
        @session.send %Q{
            new Table(registry[#{@parent.id}], #{@id});
        }
    end
end

class Row < Widget
    def initialize(parent)
        raise "Parent must be a Table" unless parent.kind_of?(Table)
        
        super(parent)
        
        @session.send_component(Row, %q{
            function Row(mother, id) {
                var el = mother.document.createElement('tr');
                var self = new Widget(mother, id, el);
                return self;
            }
        })
        
        @session.send %Q{
            new Row(registry[#{@parent.id}], #{@id});
        }
    end
end

class Cell < Widget
    def initialize(parent)
        raise "Parent must be a Row" unless parent.kind_of?(Row)
        
        super(parent)
        
        @session.send_component(Cell, %q{
            function Cell(mother, id) {
                var el = mother.document.createElement('td');
                var self = new Widget(mother, id, el);
                return self;
            }
        })
        
        @session.send %Q{
            new Cell(registry[#{@parent.id}], #{@id});
        }
    end
end






# OLD WIDGETS ARE BELOW
if false
class Frame < Container
    def initialize(parent)
        super(parent)
        
        # This is basically a div
        @session.send %Q{
            var widget = registry[#{@parent.id}].display.createElement('div');
            widget.style.borderWidth = '0';
            widget.style.margin = '0';
            widget.style.padding = '0';
            registry[#{@id}] = widget;
            registry[#{@id}].display = registry[#{@parent.id}].display;
            registry[#{@parent.id}].appendChild(widget);
        }
    end
end

class IFrame < Widget
    def initialize(parent, src='')
        super(parent)
        
        @src = src
        
        @session.send %Q{
            var widget = registry[#{@parent.id}].display.createElement('iframe');
            widget.src = '#{WebApp.escape_string(@src)}';
            widget.frameborder = '0';
            widget.style.border = '0';
            widget.style.padding = '0';
            widget.style.margin = '0';
            widget.style.width = '100%';
            widget.style.height = '100%';
            registry[#{@id}] = widget;
            registry[#{@parent.id}].appendChild(widget);
        }
    end
    
    def src
        @src
    end
    
    def src=(src)
        if @src != src
            @src = src
            @session.send %Q{
                registry[#{@id}].src = '#{WebApp.escape_string(@src)}';
            }
        end
    end
end

# Module to include in a widget that can serve a Response object for itself
# if queried by the client. It will also report its URI for accessing this
# resource.
module ServerWidget
    def uri
        "#{@session.referer}widget?sid=#{@session.sid}&id=#{@id}"
    end
    
    def serve
        nil # Return a nil response by default
    end
end

class DocumentFrame < IFrame
    include ServerWidget
    
    def initialize(parent, document)
        super(parent)
        
        @document = document
        
        self.src=uri
    end
    
    def serve
        @document
    end
end

HTMLFrame = DocumentFrame

class PDFFrame < DocumentFrame
    def initialize(parent, pdfdata)
        super(parent, Response.new(pdfdata, 'application/pdf'))
    end
end

# Include some other widget sets.
require 'menu.rb'
require 'subwindow.rb'
require 'layout.rb'
require 'tab.rb'
end
