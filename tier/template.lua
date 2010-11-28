require "tier.util"

module("tier", package.seeall)

local copy = tier.copy

-- view could be a text node, a {{...}}, or a template 
View = tier.Type("View")
function View:__init(t, path, src, loc)
    -- A table for subclasses to save state
    self.args = {}
    
    -- The file path of the view of the template it belongs to
    self.path = path
    
    -- The directory used for opening more template files
    self.directory = path and tier.dir(path) or nil
    assert(type(loc)=="number" or loc == nil)
    
    -- Character index the view occurs in the template file
    self.loc = loc
    
    -- The source of the template file
    self.src=src
    local target = nil
    if type(t)=="string" then
        self.src = self.src or t
        target = self:parse(t)
    elseif type(t) == "table" then
        target = t --tier.clone(t)
    end
    assert(target, "view argument must be table or string")
    return copy(target, self)
end
function View:parse(str)
    error("view:parse not implemented.")
end
function View:render(args, list)
    error("view:render not implemented.")
end

-- a simple text node in a template
Text = tier.inherit(View, "Text")
function Text:parse(str)
    return { value = str }
end
function Text:render(args, list)
    return self.value
end
function Text:__tostring()
    return "Text{"..tostring(self.value).."}"
end
-- a {%...%} or {{...}} node in a template
Tag = tier.inherit(View, "Tag")
function Tag:parse(str)
    self.name = str:sub(2, 2)
    return self[self.name](self, str)
end

Tag['%'] = function(self, str)
    -- extract tag name and select its render method
    assert(str:sub(#self-2, #self-2) == '%')
    local new = {args = str:sub(3, #self-3):trim():split(' ')}
    new.name = table.remove(new.args, 1)
    local render = self['_'..new.name]
    assert(type(render) == "function", new.name.." tag does not exist.")
    new.render = render
    return new
end

Tag['{'] = function(self, str)
    -- convert to {% arg .. %} tag
    assert(str:sub(#self-2, #self-2) == '}')
    local new = {args={str:sub(3, #self-3):trim()}}
    new.render = self._arg
    new.name = "arg"
    return new
end

function Tag:parse_blocks(list, fn, level)
    -- find each block when level == 0 and call fn with it
    level = level or 0
    local current = level > 0 and {id="", list=tier.List{}} 
                               or {id=nil, list=nil}
    local prev=list.first
    for l, tag in tier.List(list.second):iter() do
        if current.id and level > 0 then
            current.list:append(tag)
        end
        if level==0 and tier.typeof(tag)==Text then
            list:remove(prev)
        elseif tag.name == "block" then
            level=level+1
        elseif tag.name == "endblock" then
            level=level-1
        end
        if level == 1 and tag.name == "block" then
            current.id = tag.args[1]
            current.list = tier.List{}
        elseif level == 0 and tag.name == "endblock" then
            local ar = current.list:array()
            table.remove(ar)
            local block = Template(ar, self.path, current.list[1].src)
            local result = fn(current.id, block, l)
            if result ~= nil then return result end
        elseif level < 0 then
            error("Too many endblock")
        end
        prev = l.first
    end
end

function Tag:_extends(args, list)
    -- Extending a template; See Django's extends
    assert(list)
    local fn, err = loadstring("return "..self.args[1])
    if err then print("warning: "..err) end 
    setfenv(fn, args)
    local super = Template.load(self.directory.."/"..fn())
    local b = {}
    self:parse_blocks(list, function(name, block, list)
        if b[name] then
            error("Multiple blocks with same name: "..name)
        end
        args[name]=args[name] or block
        b[name] = name
    end, 0, true)
    list:truncate(list.first)
    return super:render(args) or "" -- off tail call to keep stack trace
end

function Tag:_include(args, list)
    assert(list)
    local fn, err = loadstring("return "..self.args[1])
    if err then print("warning: "..err) end 
    setfenv(fn, args)
    local included = Template.load(self.directory.."/"..fn())
    return included:render(args) or "" -- off tail call to keep stack trace
end

function Tag:_block(args, list)
    -- Block in a template; See Django's block
    assert(list)
    local name = self.args[1]
    local result = self:parse_blocks(list, function(_, block, l)
        local a = list.length
        list:truncate(list.first)
        list:join(tier.List(l.second))
        local arg = args[name]
        if type(arg) == "string" then
            return Template(arg, self.path):render(args)
        elseif type(arg) == "table" and arg.render then
            return arg:render(args)
        elseif arg == nil then
            return block:render(args)
        else
            return tostring(arg)
        end
    end, 1)
    return result
end

function Tag:_endblock(args, list)
    -- To end `block`
    -- Should have been deleted by the matching block
    -- If not then it means endblock is unmatched
    error("Unmatched endblock tag")
    return ""
end

function Tag:_arg(args, list)
    -- evaluate arguments and render results
    -- See Django's {{...}}, but accepts lua within
    -- e.g {{ ("hello"):rep(10) }}
    assert(args)
    local value = self.value or table.concat(self.args, " ")
    local fn, err = loadstring("return "..value)
    if err then 
        print("warning "..tier.linenumber(self.src, self.loc)..": "..err) 
        print("source:\n"..self.src)
    end 
    if fn then
       setfenv(fn, args)
       local result = fn()
       return result ~=nil and tostring(result)
    end
    return nil
end

function Tag:parse_lua(list, fn, control, open, close)
    assert(self.path)
    local level, index = 0, 1
    local block = {}
    open = open or {control[1]}
    close = close or {control[#control]}
    
    local find = tier.find
    
    for l, tag in list:iter() do
        if find(close, tag.name) then
            level = level - 1
        end
        local i = find(tier.sub(control, index), tag.name)
        local j = find(control, tag.name)
        if i and (level == 0 or level==1 and j~=1 and j~=#control) then
            local name = control[j]
            local code = name.." "..table.concat(tag.args, " ")
            local result = fn(name, code, 
                Template(block, self.path, #block > 0 and block[1].src), l)
            block = {}
            index = i + 1
            if result then return result end
        else
            table.insert(block, tag)
        end
        if find(open, tag.name) then
            level = level + 1
        end
    end
end
function Tag:run_lua(args, fn, scope)
    setfenv(fn, args)
    args._sc = args._sc or {}
    args._local = setmetatable({}, {__index = function(t, k, v) 
        return args._sc[#args._sc][k]
    end})
    table.insert(args._sc, scope)
    fn()
    table.remove(args._sc)
end

function Tag.make_control(struct, open, close)
    -- Creates control tags
    local start = struct[1]
    local finish = struct[#struct]
    Tag["_"..start] = function(self, args, list)
        local code = {}
        local blocks, out = {}, {}
        local i = 1
        local skipped_to=nil
        self:parse_lua(list, function(name, line, block, l)
            skipped_to = l
            table.insert(blocks, block)
            -- render previous block
            table.insert(code, ([[table.insert(_local.out, _local.blocks[%d]:render(_G))]]):format(i))
            -- render the line of lua in {% ... %}
            table.insert(code, line)
            -- make all local variables global
            table.insert(code, [[tier.copy(tier.scope(), _G)]])
            i=i+1
            if name == finish then
                return true
            end
        end, struct, open, close)
        list:truncate(list.first)
        list:join(skipped_to)
        local fn, err = loadstring(table.concat(code, " "))
        if err then print("warning: "..err) print(table.concat(code, " ")) end 
        self:run_lua(args, fn, {out=out, blocks=blocks})
        return table.concat(out) or ""
    end
    for i, v in ipairs(struct) do
        Tag["_"..v] = Tag["_"..v] or function() end
    end
end

Tag.make_control({"repeat", "until"}, {"repeat"}, {"until"})
local open, close ={"if", "while", "for", "function"}, {"end"}
Tag.make_control({"while", "end"}, open, close)
Tag.make_control({"for", "end"}, open, close)
Tag.make_control({"if", "elseif", "else", "end"}, open, close)


function Tag:__tostring()
    return "Tag{"..self.name.." "..table.concat(self.args," ").."}"
end

Template = tier.inherit(View, {__type="template", prefix="./"})

function Template:parse(str)
    -- Convert a string into text & tag nodes
    local prev = 1;
    local tree = {};
    local src;
    while prev <= #str do
        local start, finish = str:find("(%b{})", prev)
        table.insert(tree, Text(str:sub(prev, (start or #str+1)-1), self.path, str, prev))
        if not start then break end
        local tag = str:sub(start, finish)
        -- a tag split into multiple lines is not a tag
        -- a tag with an unknown symbol is not a tag, either
        if Tag[tag:sub(2, 2)] and not tag:find("\n") then
            table.insert(tree, Tag(tag, self.path, str, start))
        else
            table.insert(tree, Text(tag, self.path, str, start))
        end
        prev=finish+1
    end
    return tree
end

function Template:render(args)
    -- Render the template with these arguments
    args = args or {}
    setmetatable(args, {__index=_G})
    args._G=args
    local html = {}
    -- convert template to linked-list so can be easily manipulated
    -- local tree = tier.list(tier.clone(self)) -- not cloning is faster, but is it safe?
    local list = tier.List(self)
    for l, val in list:iter() do
        local error_message = ""
        local error_traceback = ""
        local error_source = ""
        local function render()
            return val:render(args, l)
        end
        local function handler(err) 
            local line = tier.linenumber(self.src, val.loc)
            error_message = "Line "..line..": "..err
            error_traceback = debug.traceback("", 2)
        end
        local success, result = xpcall(render, handler)
        if not success then
            error_source = self.src
            return Template.error():render{message = error_message, 
                                           traceback = error_traceback,
                                           source = error_source}
        else
            table.insert(html, tostring(result~=nil and result or ""))
        end
    end
    return table.concat(html)
end

function Template.load(path)
    -- Load template from file
    local file = io.open(path)
    assert(file, path.." file not found")
    local str = file:read("*a")
    return Template(str, path)
end

function Template.default()
    return Template([[
<!doctype html>
<html>
  <head>
    {% block head %}
      <title>{% block title %}{% endblock %}</title>
      {% block css %}{% endblock %}
      {% block js %}{% endblock %}
    {% endblock %}
    {% block extra-head %}
    {% endblock %}
  </head>
  <body>
    {% block errors %}{% endblock %}
    {% block header %}{% endblock %}
    {% block content %}{% endblock %}
    {% block footer %}{% endblock %}
  </body>
</html>
]])
end

function Template.error()
    return Template([[
<!doctype html>
<html>
  <head>
    <title>Template Error</title>
    <style>
        body { font-family:Arial; }
        h1 { font-size: large; }
        h2 { font-size: medium; }
        textarea { border: 1px gray solid;
        font-size: small; }
    </style>
  </head>
  <body>
    <h1>{{ message }}</h1>
    <h2>Traceback</h2>
    <pre>{{ traceback }}</pre>
    <h2>Source</h2>
    <textarea disabled cols=80 rows=15>{{ source }}</textarea>
  </body>
</html>
]])
end
