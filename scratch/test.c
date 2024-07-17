#include <stdio.h>

typedef struct {
  int a;
  int b;
  int sum;
} result_t;

result_t add(int a, int b) {
  const result_t res = {
    .a = a,
    .b = b,
    .sum = a + b,
  };

  return res;
}

void loop(void) {
  const char* name = "hello";
  for (int i = 0; i < 5; i++) {
    printf("%c\n", name[i]);
  }
}

int main (void) {
  int a = 10;
  int b = 2;

  add(a, b);
  loop();

  return 0;
}
