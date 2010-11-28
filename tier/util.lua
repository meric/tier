
module("tier", package.seeall)

-- from http://lua-users.org/wiki/StringTrim
function string:trim()
    local a = self:match('^%s*()')
    local b = self:match('()%s*$', a)
    return self:sub(a,b-1)
end

-- from http://lua-users.org/wiki/SplitJoin
function string:split(sep)
    local sep, fields = sep or " ", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

-- Get the directory a file resides in
function dir(path)
    return path:match("^.*/") or ""
end

-- get line number at index
function linenumber(str, index)
    local i = 0
    local line = 1
    assert(index <= #str, index)
    while i <= index do
        local start, finish = str:find("\n", i+1, true)
        i = finish
        line = line + 1
        if not i then 
            return 1 
        end
    end
    return i<=index and line or line-1
end

-- Subarray
function sub(t, a, b)
    b = b or #t
    local newt = {}
    for i=a, b, 1 do
        table.insert(newt, t[i])
    end
    return newt
end


-- Index of item in array
function find(t, u)
    for i, v in ipairs(t) do
        if v == u then
            return i
        end
    end
    return nil
end

-- Update table
function update(t, t1)
    for k, v in pairs(t1) do
        t[k]=v
    end
    return t
end

-- from http://stackoverflow.com/questions/2834579/
-- Get the local scope
function scope()
    local variables = {}
    local idx = 1
    while true do
        local ln, lv = debug.getlocal(2, idx)
        if ln ~= nil then
            variables[ln] = lv
        else
            break
        end
        idx = 1 + idx
    end
    return variables
end

-- copy u to w
function copy(u, w)
    for i, v in pairs(u) do
        w[i]=v;
    end
    return w
end

-- Represent table in string form
-- Is Lossy, Has Collisions
function serialize(t)
    local o = {}
    for k, v in pairs(t) do
        table.insert(o, tostring(k).."="..tostring(v))
    end
    return table.concat(o, ";")
end

-- escape html
function escape_html(s)
    local replacement = {"<", "&lt;", 
                         ">", "&gt;", 
                         "{{", "\n<span>{{</span>\n",
                         "{%%", "\n<span>{%%</span>\n",
                         "%%}", "\n<span>%%}</span>\n",
                         "}}", "\n<span>}}</span>\n"}
    local str, n = s, 0;
    for i=1, #replacement, 2 do
        str, n = str:gsub(replacement[i], replacement[i+1]);
    end
    return str
end

-- Complete clone of a table
function clone(u, copied)
    copied = copied or {}
    local new = {}
    copied[u] = new
    for k, v in pairs(u) do
        if type(v) ~= "table" then
            new[k] = v
        elseif copied[v] then
            new[k] = copied[v]
        else
            copied[v] = clone(v, copied)
            new[k] = setmetatable(copied[v], getmetatable(v))
        end
    end
    setmetatable(new, getmetatable(u))
    return new
end

-- type
Type = {__type="Type", __tostring=function(self) 
    return tostring(self.__type) 
end}

setmetatable(Type, {__call = function(self, t)
    if type(t)=="string" then
        t = {__type=t}
    end
    t = setmetatable(t or {}, Type)
    t.__index = t
    return t
end})

function Type:__init(t) 
    copy(t or {}, self);
    return self
end

function Type:__call(...)
    local object = setmetatable({}, self)
    local r_object = self.__init(object, ...)
    object = r_object or object;
    return object
end

function inherit(parent, t)
    assert(parent)
    if type(t)=="string" then
        t = {__type=t}
    end
    local newt = copy(t or {}, copy(parent, {__super=parent}))
    return Type(newt)
end

function super(t)
    assert(t)
    return t.__super
end

-- return the type of o
function typeof(o)
    return getmetatable(o)
end


Pair = Type("Pair")
function Pair:__init(first, second)
    self.car = first
    self.cdr = second
    return self
end

function Pair:__tostring()
    return "["..tostring(self.car).." "..tostring(self.cdr).."]"
end

List = Type("List")
function List:__init(t, start)
    start = start or 1
    self.length = 0
    if type(t)=="table" and t.__type=="Pair" then
        self.first = t
        self.length = 1
        while t.cdr do
            self.length = self.length + 1
            t=t.cdr
        end
        self.last = t
    elseif type(t) == "table" then
        for i = start, #t, 1 do
            self:append(t[i])
        end
        self.length = #t - start + 1
    else
        self.length = 0
        self.first = nil
        self.last = nil
    end
end

function List:__tostring()
    return "{"..tostring(self.first).."}"
end

function List:__index(key)
    if type(key) == "number" then
        if key > self.length then
            return nil
        end
        local node = self.first
        for i=1, key, 1 do
            if key == i then
                return node.car
            end
            node = node.cdr
        end
        return nil
    end
    if key == "second" then
        return self.first and self.first.cdr or nil
    end
    return getmetatable(self)[key]
end

function List:__concat(l)
    return util.clone(self):join(util.clone(l))
end


function List:join(l)
    local left = self
    local right = l
    left.last.cdr = right.first
    left.last = right.last
    left.length = left.length + right.length
    return left
end

-- list as array
function List:array()
    local t ={}
    for n, v in self:iter() do
        table.insert(t, v)
    end
    return t
end

-- remove the node after prev
function List:remove(prev)
    local rm = prev.cdr
    if rm then
        prev.cdr = rm.cdr 
        self.length = self.length - 1
    end
    return rm
end

-- insert an item after prev
function List:insert(prev, item)
    local nx = prev.cdr
    prev.cdr = Pair(item, nx)
    self.length = self.length + 1
    return item
    
end

-- remove all nodes after prev
function List:truncate(prev)
    assert(prev)
    self.last = prev
    prev.cdr = nil
    local node = self.first
    self.length = 1
    while node.cdr do
        self.length = self.length + 1
        node = node.cdr
    end
    return self
end

-- append item to list
function List:append(i)
    if self.length == 0 then
        self.first = Pair(i, nil)
        self.last = self.first
        self.length = 1
    else
        self.last.cdr = Pair(i, nil)
        self.last = self.last.cdr
        self.length = self.length + 1
    end
    return self
end

function List:prepend(i)
    if self.length == 0 then
        self.first = Pair(i, nil)
        self.last = self.first
        self.length = 1
    else
        self.first = Pair(i, self.first)
        self.length = self.length + 1
    end
    return self
end

function List:iter()
    local i = 0
    local prev = Pair(nil, self.first)
    return function()
        local node = prev.cdr
        if not node then 
            return nil 
        end
        prev, node = node, node.cdr
        return List(prev), prev.car
    end
end


