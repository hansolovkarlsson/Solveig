program Nested(output);
{ Nested procedures and uplevel access. A block captures the frame it was made
  in, and a nested procedure's block is made anew every time its parent runs --
  so OP_OUTER reaches the right activation without anything being said about
  activations. }
var g : integer;

procedure Outer(n : integer);
var total : integer;

  procedure Add(k : integer);
  begin
    total := total + k
  end;

  procedure Twice(k : integer);
  begin
    Add(k);
    Add(k)
  end;

  function Doubled : integer;
  begin
    Doubled := total * 2
  end;

begin
  total := n;
  Add(1);
  Twice(10);
  writeln(total:6, Doubled:6)
end;

{ Two levels out: Deep reads a variable of Top, past Middle. }
procedure Top;
var mark : integer;

  procedure Middle;
  var own : integer;

    procedure Deep;
    begin
      write(mark:4, own:4)
    end;

  begin
    own := 2;
    Deep
  end;

begin
  mark := 1;
  Middle;
  writeln
end;

{ Recursion of the enclosing procedure: each activation gets its own `mine`,
  and its own Show bound to that activation. }
procedure Nest(depth : integer);
var mine : integer;

  procedure Show;
  begin
    write(mine:4)
  end;

begin
  mine := depth;
  Show;
  if depth > 1 then Nest(depth - 1);
  Show
end;

{ A nested procedure writing an enclosing var parameter, so the write has to
  travel out a frame and then through a box. }
procedure Fill(var out : integer);

  procedure Put(v : integer);
  begin
    out := v
  end;

begin
  Put(77)
end;

begin
  Outer(100);
  Top;
  Nest(3);
  writeln;
  Fill(g);
  writeln(g:4)
end.
