# What's this?

This is a [Lama](https://github.com/PLTools/Lama) bytecode interpreter for Virtual Machines course.

# Usage

## Pre-requisites

You should have Zig installed. The latest version is mandatory. You can download pre-built binaries from [here](https://ziglang.org/download/).

Then check your version with `zig version`:
```
~  =>  zig version
0.16.0-dev.747+493ad58ff
```

## Running

You can run a `*.bc` file with the following command:
```
make run FILE=<path_to_bc_file>
```

Which will build the interpreter and run the bytecode file. The interpreter executable itself will be in `$(pwd)/build` directory.

## Testing

Tests reside in `src/main.zig` and can be run with:
```
~  => make test
Building LamaRpreter with Zig...
LamaRpreter copied to build/
Running tests...
test
└─ run test stderr
File location: /home/safonoff/Uni/VirtualMachines/LamaRpreter/dump/test1.bc.

Build Summary: 3/3 steps succeeded; 1/1 tests passed
test success
└─ run test 1 passed 8ms MaxRSS:5M
   └─ compile test Debug native cached 14ms MaxRSS:37M
```
