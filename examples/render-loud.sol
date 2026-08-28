; render-loud.sol -- the other module. Same shape, different answer.
renderer := object:new.
renderer:name := "loud".
renderer:show := { text | text:asUppercase:concat("!") }.
renderer:exports(['name, 'show]).
