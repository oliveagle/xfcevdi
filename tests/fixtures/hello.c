#include <stdio.h>
#include <stdlib.h>

int add(int a, int b) { return a + b; }

int main(void) {
    if (add(2, 3) != 5) {
        return 1;
    }
    printf("xfcevdi toolchain OK\n");
    return 0;
}
