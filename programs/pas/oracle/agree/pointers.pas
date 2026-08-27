program Pointers(output);
{ A pointer is a one-element cell, `new` makes one holding a zero of whatever
  is pointed at, and `nil` is the machine's own. `dispose` frees nothing --
  SolVM is collected -- which docs/PASCAL.md records as a divergence and
  differ/dispose.pas exercises.

  A pointer type may name a type declared after it, and has to: there is no way
  to write a linked structure the other way round. }
type Link = ^Node;
     Node = record value : integer; next : Link end;
     Tree = ^Branch;
     Branch = record key : integer; left, right : Tree end;
var head, p : Link;
    root : Tree;
    i : integer;

procedure Insert(var t : Tree; k : integer);
begin
  if t = nil then
    begin
      new(t);
      t^.key := k;
      t^.left := nil;
      t^.right := nil
    end
  else if k < t^.key then Insert(t^.left, k)
  else if k > t^.key then Insert(t^.right, k)
end;

procedure InOrder(t : Tree);
begin
  if t <> nil then
    begin
      InOrder(t^.left);
      write(t^.key:4);
      InOrder(t^.right)
    end
end;

function Depth(t : Tree) : integer;
var l, r : integer;
begin
  if t = nil then Depth := 0
  else
    begin
      l := Depth(t^.left);
      r := Depth(t^.right);
      if l > r then Depth := l + 1 else Depth := r + 1
    end
end;

begin
  head := nil;
  writeln(head = nil, head <> nil);

  for i := 5 downto 1 do
    begin
      new(p);
      p^.value := i * i;
      p^.next := head;
      head := p
    end;

  p := head;
  while p <> nil do
    begin
      write(p^.value:5);
      p := p^.next
    end;
  writeln;

  { A pointer assigned is the same cell, not a copy of what it points at. }
  p := head;
  p^.value := 99;
  writeln(head^.value:4);

  root := nil;
  Insert(root, 50);
  Insert(root, 30);
  Insert(root, 70);
  Insert(root, 20);
  Insert(root, 40);
  Insert(root, 60);
  Insert(root, 80);
  InOrder(root);
  writeln;
  writeln(Depth(root):4);
  writeln(root^.key:4, root^.left^.key:4, root^.right^.key:4)
end.
