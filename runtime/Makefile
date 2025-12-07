build:
	@echo "Building runtime..."
	clang -fstack-protector-all -g -c gc.c -o gc.o
	clang -fstack-protector-all -g -c runtime.c -o runtime.o
	clang -Wa,--noexecstack -x assembler-with-cpp -c -g printf.S -o printf.o
	ar rcs libruntime.a gc.o runtime.o printf.o
