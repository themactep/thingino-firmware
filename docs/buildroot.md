Buildroot
=========

### Macro assignment

Use the `:=` assignment instead of `=`.

`:=` assignment causes the right hand side to be expanded immediately,
and stored in the left hand variable.

With `=` assignment every single occurrence of its macro will be
expanding the `$(...)` syntax and thus invoking the shell command.

```
FILES := $(shell ...)
# expand now; FILES is now the result of $(shell ...)

FILES = $(shell ...)
# expand later: FILES holds the syntax $(shell ...)
```
