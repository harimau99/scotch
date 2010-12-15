# these functions will be imported automatically

len(h:t) = 1 + len(t)
len([]) = 0

head(h:t) = h
tail(h:t) = t
reverse(h:t) = reverse(t) + h
reverse([]) = []

join(h:t, s) = h + if len(t) > 0 then s + join(t, s) else ""

all(h:t) = if h then all(t) else false
all([]) = true
any(h:t) = if h then true else any(t)
any([]) = false

prefix(a:b, c:d) = if a == c then prefix(b, d) else false
prefix(a, []) = false
prefix([], c) = true
suffix(a, c) = prefix(reverse(a), reverse(c))

lstrip(h:t) = lstrip(h:t, " ")
lstrip(h:t, s) = if h == s then lstrip(t, s) else h + t
rstrip(h:t) = rstrip(h:t, " ")
rstrip(a, s) = lstrip(reverse(a), s)
strip(h:t) = strip(h:t, " ")
strip(h:t, s) = lstrip(rstrip(h:t, s), s)
