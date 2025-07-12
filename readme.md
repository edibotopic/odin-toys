# Odin toys

Little experiments with the Odin programming language.

## Examples

* Pong game
* Node connector
* cat command

## Running

To compile and run examples you will need to have Odin [installed](https://odin-lang.org/docs/install/) and on your path.

After you `git clone` this repo, change to an example `<example>` directory and run `make`.

```bash
cd <example>
make
```

This will build the `<example>` executable in the `/bin/` directory.
On Linux, this can then be run with `./bin/<example>`.

Note that the makefile invokes `odin` with a `-o:speed` flag
to optimise for performance:

```bash
odin build . -o:speed -out:bin/<example>
```

If you want to develop with the code just run:

```bash
odin run . -out:bin/<example>
```

This will compile faster and also run the executable.
