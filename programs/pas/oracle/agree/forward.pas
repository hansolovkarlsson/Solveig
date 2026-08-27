program Forward(output);
{ forward: the heading is given once and the body repeats only the name, so a
  call may be compiled long before there is anything to call. Two procedures
  that call each other need it. }
var n : integer;

function IsOdd(k : integer) : boolean; forward;

function IsEven(k : integer) : boolean;
begin
  if k = 0 then IsEven := true
  else IsEven := IsOdd(k - 1)
end;

function IsOdd;
begin
  if k = 0 then IsOdd := false
  else IsOdd := IsEven(k - 1)
end;

procedure Show(k : integer); forward;

procedure Show;
begin
  write(k:3, IsEven(k):7)
end;

begin
  for n := 0 to 5 do
    begin
      Show(n);
      writeln
    end
end.
