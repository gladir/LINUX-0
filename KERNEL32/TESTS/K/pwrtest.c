/* pwrtest : arret et redemarrage ACPI (init= de RUNPOWER.SH). La ligne de
   commande contient noportoff (le noyau n'essaie ni les ports d'arret de
   QEMU/Bochs/VirtualBox, ni le controleur 8042, ni la triple faute) et
   k32restart ou k32off : si QEMU s'arrete (-no-reboot), l'ACPI a marche. */
#include "ku.h"
int main(void){
  puts("PWR-START\n");
  sync();
  if(ku_cmdline_has("k32restart"))sc4(SYS_reboot,0xfee1dead,672274793,0x01234567,0);
  else sc4(SYS_reboot,0xfee1dead,672274793,0x4321FEDC,0);
  puts("PWR-NOT-REACHED\n");
  return 1;
}
