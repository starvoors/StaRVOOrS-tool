package main;

public class CMachine {
   
   public int cups;
   public int limit;
   public boolean active;
   public Integer x;
   
   CMachine(int limit) {
        this.limit = limit;
        cups = 0;
        active = false;
   }

   public void cleanF() {
       if (!active)
          cups = 0;
   }

   public void brew() {
       if (!active && cups < limit) 
          cups++;
   }

   public int brew(int m) {
       return m ;
   }

   public boolean brew(int n,boolean b) {
       return b ;
   }

   public int getCups() { return cups;}

}
