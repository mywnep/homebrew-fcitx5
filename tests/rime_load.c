#include <dlfcn.h>
#include <stdio.h>
#include <stdbool.h>
// These layout flags are normally exported by the Fcitx5 host executable.
bool f5m_is_linear_layout = false;
bool f5m_is_vertical_lr = false;
bool f5m_is_vertical_rl = false;
int main(int argc, char **argv) {
  if (argc != 2) return 2;
  void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 1; }
  if (!dlsym(handle, "fcitx_addon_factory_instance_rime")) return 3;
  const char *(*version)(void) = dlsym(handle, "_Z14RimeGetVersionv");
  if (!version) { fprintf(stderr, "%s\n", dlerror()); return 4; }
  printf("PASS dlopen + Fcitx factory symbol + librime version: %s\n", version());
  dlclose(handle);
  return 0;
}
