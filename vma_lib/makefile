$(CXX)=g++

all: vma.cpp;
	$(CXX) -I../VulkanMemoryAllocator-3.2.1/include -c -fPIC vma.cpp -o vma.o
	$(CXX) -shared vma.o -o libvma.so
