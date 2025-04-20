$(CXX)=g++

all: vma.cpp;
	$(CXX) -c -fPIC vma.cpp -o vma.o
	$(CXX) -shared vma.o -o libvma.so
