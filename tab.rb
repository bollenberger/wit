class TabPane < Widget
    attr_reader :tabs_id
    
    def initialize(parent)
        super(parent)
        
        @session.send_component TabPane, %q{
            function TabPane(parent, id) {
                var el = parent.document.createElement('div');
                var self = new Widget(parent, id, el);
                self.tabs = parent.document.createElement('div');
                self.tabs.style.borderWidth = '0px';
                //self.tabs.style.borderWidth = '0px 0px 1px 0px';
                //self.tabs.style.borderColor = 'ThreeDDarkShadow';
                //self.tabs.style.borderStyle = 'solid';
                el.appendChild(self.tabs);
                
                self.active = null;
                
                self.activate = function (tab) {
                    if (self.active!=tab) {
                        if (self.active!=null) {
                            self.active.deactivate();
                        }
                        self.active = tab;
                    }
                };
                
                self.deactivate = function (tab) {
                    if (self.active==tab) {
                        self.active = null;
                    }
                };
                
                return self;
            }
        }
        
        @session.send %Q{
            new TabPane(registry[#{@parent.id}], #{@id});
        }
    end
    
    # To be called only from Tab::activate
    def activate(tab)
        if @active!=tab
            @active.deactivate unless @active.nil?
            @active = tab
        end
    end
    
    # To be called only from Tab::deactivate
    def deactivate(tab)
        if @active==tab
            @active = nil
        end
    end
end

class Tab < Widget
    def initialize(parent, title)
        raise "Parent of Tab must be TabPane" unless parent.kind_of?(TabPane)
    
        super(parent)
        
        @session.send_component Tab, %q{
            function Tab(parent, id, title) {
                var tab = parent.document.createElement('div');
                var text = parent.document.createTextNode(title);
                
                // Set the height for IE - bad
                // This is because IE puts the tabs 3 pixels lower.
                // If you know a better way, tell me. Opera is still
                // problematic. It wants height=0
                var height = 1;
                if (document.all) height = -2;
                
                tab.appendChild(text);
                tab.style.MozBorderRadius = '10px 10px 0px 0px';
                tab.style.fontFamily = '"MS Sans Serif", Arial, sans-serif';
                tab.style.fontSize = '10px';
                tab.style.fontStyle = 'normal';
                tab.style.fontWeight = 'normal';
                tab.style.cursor = 'default';
                tab.style.display = 'inline';
                tab.style.margin = '2px 0px 0px 0px';
                tab.style.background = 'ThreeDFace';
                tab.style.borderWidth = '1px 1px 1px 1px';
                tab.style.borderColor = 'ThreeDLightShadow ThreeDDarkShadow '+
                    'ThreeDDarkShadow ThreeDHighlight';
                tab.style.borderStyle = 'solid';
                tab.style.position = 'relative';
                tab.style.padding = '2px 5px 1px 5px';
                tab.style.top = (height+1)+'px';
                parent.tabs.appendChild(tab);
                var el = parent.document.createElement('div');
                el.style.display = 'none';
                
                var self = new Widget(parent, id, el);
                
                self.remove = function () {
                    self.parent.tabs.removeChild(tab);
                };
                
                self.activate = function () {
                    parent.activate(self);
                    tab.style.borderColor = 'ThreeDLightShadow '+
                        'ThreeDDarkShadow ThreeDFace ThreeDHighlight';
                    tab.style.padding = '2px 5px 2px 5px';
                    tab.style.top = height+'px';
                    self.element.style.display = 'block';
                };
                
                self.deactivate = function () {
                    tab.style.borderColor = 'ThreeDLightShadow '+
                        'ThreeDDarkShadow ThreeDDarkShadow ThreeDHighlight';
                    tab.style.padding = '2px 5px 1px 5px';
                    tab.style.top = (height+1)+'px';
                    self.element.style.display = 'none';
                };
                
                tab.onclick = function () {
                    self.activate();
                    self.send('click');
                }
                
                return self;
            }
        }
        
        @session.send %Q{
            new Tab(registry[#{@parent.id}], #{@id},
                '#{WebApp.escape_string(title)}');
        }
        
        @active = false
        
        set_event('click') do
            activate
        end
    end
    
    def onactivate(&block)
        @onactivate = block
    end
    
    def ondeactivate(&block)
        @ondeactivate = block
    end
    
    def active
        @active
    end
    
    def active=(act)
        if act
            activate
            @session.send "registry[#{@id}].activate();"
        else
            deactivate
            @session.send "registry[#{@id}].deactivate();"
        end
    end
    
    # These (activate and deactivate) are only called from TabPane.
    # Use active= instead.
    def activate
        @parent.activate(self)
        @active = true
        @onactivate.call unless @onactivate.nil?
    end
    
    def deactivate
        @parent.deactivate(self)
        @active = false
        @ondeactivate.call unless @ondeactivate.nil?
    end
end
