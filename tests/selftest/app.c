__declspec(dllimport) int demo_dep(void);
int main(void) { return demo_dep() - 1; }
