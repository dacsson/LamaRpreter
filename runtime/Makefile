build:
	@echo "Building runtime..."
	gcc -c gc.c -o gc.o
	gcc -c runtime.c -o runtime.o
	ar rcs libruntime.a gc.o runtime.o
