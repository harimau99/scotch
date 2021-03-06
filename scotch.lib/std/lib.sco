# these functions will be imported by the Scotch interpreter automatically

version = do import std.version
copyright = do import std.copyright
license = do import std.license
about = do import std.about


# Returns the length of a string or list.
len(h:t, a) = len(t, a + 1)
len([], a) = a
len(l) = len(l, 0)
length = len

# Returns the first element in a string or list.
head(h:t) = h
head([]) = []
# Returns a list or string, minus the first element.
tail(h:t) = t
tail([]) = []
# Returns the last element in a list
last(h:t) = (l) @ (len(l) - 1) 
            where l := (h:t)
# Returns a list or string in reverse order.
reverse(h:t) = [for i in [len(h:t) - 1 .. 0, -1], (h:t) @ i]

# Joins the members of a list, separating them by string \s.
join(h:t, s) = h + (if len(t) > 0 then s + join(t, s) else "")

# Returns true only if all of the members in a list are true.
all(l) = foldr((x, y) -> x & y, l, true)
# Returns true if any of the members in a list are true.
any(l) = foldr((x, y) -> x | y, l, false)

# Checks whether string/list \c+d is a prefix of \a+b.
prefix(a:b, c:d) = if a == c then prefix(b, d) else false
prefix([], c) = true
prefix(a, []) = false
# Checks whether string/list \c is a prefix of \a.
suffix(a, c) = prefix(reverse(a), reverse(c))
infix(a:b, c:d) = if prefix(a:b, c:d) then true else prefix(a:b, d)
infix(a:b, d) = false

# Returns true if \h:t contains element/sequence \s.
contains(h:t, s) = if (h == s) then true else contains(t, s)
contains([], s) = false

# Returns the number of times \s appears in \h:t.
count(h:t, s, a) = count(t, s, a + (if prefix(h:t, s) then 1 else 0))
count([], s, a) = a
count(l, s) = count(l, s, 0)

# Removes all characters in \s from the left of a string.
lstrip(h:t, s) = if contains(s, h) then lstrip(t, s) else h:t
lstrip([], s) = []
lstrip(h:t) = lstrip(h:t, " ")
# Removes all characters in \s from the right of a string.
rstrip(a, s) = reverse(lstrip(reverse(a), s))
rstrip(h:t) = rstrip(h:t, " ")
# Removes all characters in \s from the left and right of a string.
strip(h:t) = strip(h:t, " ")
strip(h:t, s) = rstrip(lstrip(h:t, s), s)

# Splits a string into a list of strings separated by character \s.
split(h:t, s) = if len(s) == 1 
                then splitChar(h:t, s, [], [])
                else splitSeq(h:t, s, [], [])
splitChar(h:t, s, a, b) = if s == h
                          then splitChar(t, s, a + [b], [])
                          else splitChar(t, s, a, b + h)
splitChar([], s, a, b) = a + [b]
splitSeq(h:t, s, a, b) = if prefix(s, h:t)
                         then splitSeq(right(h:t, len(h:t) - len(s)), s, a + [b], [])
                         else splitSeq(t, s, a, b + h)
splitSeq([], s, a, b) = a + [b]
lines(f) = split(read(f), "\n")

join(h:t, s) = if t == []
               then h
               else h + s + join(t, s)
join([], s) = ""

# Replaces all instances of \s with \r.
replace(h:t, s, r) = if prefix(s, h:t) 
                     then r + replace(right(h:t, len(h:t) - len(s)), s, r) 
                     else h + replace(t, s, r)
replace([], s, r) = []

only(h:t, s) = (if contains(s, h) then h else "") + only(t, s)
only([], s) = []

left(h:t, n) = take n from h:t
left(h:t, 0) = []
left([], n) = []
right(h:t, n) = [for i in [if l > n then (l - n) else 0 .. l - 1], (h:t) @ i] where l := len(h:t)

foldl(f, h:t, z) = foldl(f, t, f(z, h))
foldl(f, [], z) = z
foldr(f, h:t, z) = f(h, foldr(f, t, z))
foldr(f, [], z) = z
reduce = foldl

filter(f, l) = [for i in l, i, f(i)]
filter(f, []) = []
map(f, l) = [for i in l, f(i)]

show(a) = str(a)

sum(h:t, s) = foldr((x, y) -> x + y, h:t, s)
sum(l) = sum(l, 0)
prod(h:t) = foldr((x, y) -> x * y, h:t, 1)

sort(h:t) = qsort(h:t)
qsort(h:t, n) = (case (len(h:t) < n) of
                   true -> h:t,
                   false -> (qsort(less) : h : qsort(more))
                  where less = filter((x) -> h > x, t), more = filter((x) -> h < x, t))
qsort([], n) = []
qsort(l) = qsort(l, 1)
insert(x, h:t, a) = if x > h then h + insert(x, t) else ([x] + [h] + t)
insert(x, [], a) = a + x
insort(h:t) = insert(h, (insort(t)))
insort([]) = []

execute(h:t) = eval(right(left(s, l-1), l-2))
               where s := str(h:t), l := len(s)
execute([]) = skip

repeat(f, r, n) = repeat(f, f(r), n-1)
repeat(f, r, 0) = r

zip(a:b, c:d) = [[a,c]] + zip(b, d)
zip([], []) = []
zip([], c:d) = []
zip(a:b, []) = []
zip(a:b, c:d, f) = [f(a, c)] + zip(b, d, f)
zip([], [], f) = []
zip([], c:d, f) = []
zip(a:b, [], f) = []


do (+)(x, y) = x + y,
   (-)(x, y) = x - y,
   (*)(x, y) = x * y,
   (/)(x, y) = x / y,
   (^)(x, y) = x ^ y,
   (&)(x, y) = x & y,
   (|)(x, y) = x | y,
   (==)(x, y) = x == y,
   (!=)(x, y) = x != y
