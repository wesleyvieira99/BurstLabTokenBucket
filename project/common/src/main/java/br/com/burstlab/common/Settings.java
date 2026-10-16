package br.com.burstlab.common;
public final class Settings {
 private Settings() {}
 public static String env(String name,String fallback){String v=System.getenv(name);return v==null||v.isBlank()?fallback:v;}
 public static int integer(String name,int fallback){return Integer.parseInt(env(name,""+fallback));}
 public static boolean flag(String name){return Boolean.parseBoolean(env(name,"false"));}
}
