

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

int main (void) {
  int a = 10;
  int b = 2;

  add(a, b);

  return 0;
}
