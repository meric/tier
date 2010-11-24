require 'tier.template'
local a = tier.Template.load("templates/example2.html")
print(a:render{planet="Earth", 
               answer=function() return "42" end, 
               name="example2.html",
               replaced="--replaced by a block--"})