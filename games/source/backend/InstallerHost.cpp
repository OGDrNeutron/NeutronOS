// App-owned Wine installer host. Controller commands are delivered only to
// windows belonging to the launched installer tree in this private prefix.
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <string>
#include <vector>
#include <set>
#include <fstream>
#include <algorithm>
#include <cwctype>
#include <cstdlib>
#include <cstdio>
static std::set<DWORD> owned;
static HWND installerWindow=nullptr;
static bool msi=false;
static bool installerProcess(DWORD pid){
 if(owned.count(pid))return true;
 if(!msi)return false;
 HANDLE h=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);if(!h)return false;
 wchar_t path[4096];DWORD size=4096;bool valid=QueryFullProcessImageNameW(h,0,path,&size)!=0;CloseHandle(h);
 if(!valid)return false;std::wstring name(path,size);auto slash=name.find_last_of(L"\\/");name=name.substr(slash==std::wstring::npos?0:slash+1);std::transform(name.begin(),name.end(),name.begin(),::towlower);
 return name==L"msiexec.exe";
}
static BOOL CALLBACK findWindow(HWND window,LPARAM){DWORD pid=0;GetWindowThreadProcessId(window,&pid);if(IsWindowVisible(window)&&GetWindow(window,GW_OWNER)==nullptr&&installerProcess(pid)){installerWindow=window;return FALSE;}return TRUE;}
static bool runtimeInfrastructure(const wchar_t *name){
 // Wine can start prefix services as children of the first GUI installer.
 // They outlive that installer and must not keep installation open forever.
 std::wstring base=name;auto slash=base.find_last_of(L"\\/");if(slash!=std::wstring::npos)base=base.substr(slash+1);
 const wchar_t *names[]={L"services.exe",L"winedevice.exe",L"explorer.exe",L"rpcss.exe",L"plugplay.exe",L"wineboot.exe",L"winemenubuilder.exe",L"conhost.exe"};
 for(const auto *known:names)if(_wcsicmp(base.c_str(),known)==0)return true;
 return false;
}
static void descendants(){
 HANDLE snapshot=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);if(snapshot==INVALID_HANDLE_VALUE)return;
 PROCESSENTRY32W entry{};entry.dwSize=sizeof(entry);bool changed=true;
 while(changed){changed=false;if(Process32FirstW(snapshot,&entry))do{
  if(!owned.count(entry.th32ParentProcessID)||owned.count(entry.th32ProcessID))continue;
  // Wine snapshots can expose a bootstrap process before szExeFile exists.
  // Query its actual image before classifying it as an installer descendant.
  wchar_t image[4096]{};DWORD length=4096;
  HANDLE h=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,entry.th32ProcessID);
  bool identified=h&&QueryFullProcessImageNameW(h,0,image,&length)&&length;
  if(h)CloseHandle(h);
  if(!identified||runtimeInfrastructure(image))continue;
  owned.insert(entry.th32ProcessID);changed=true;
 }while(Process32NextW(snapshot,&entry));}CloseHandle(snapshot);
}
static std::wstring quote(const std::wstring &s){if(!s.empty()&&s.find_first_of(L" \t\n\v\"")==std::wstring::npos)return s;std::wstring out=L"\"";unsigned slashes=0;for(wchar_t c:s){if(c==L'\\'){slashes++;continue;}if(c==L'\"'){out.append(slashes*2+1,L'\\');out+=c;}else{out.append(slashes,L'\\');out+=c;}slashes=0;}out.append(slashes*2,L'\\');return out+L"\"";}
static void key(HWND focus,UINT value,bool shifted=false){if(shifted){PostMessageW(GetAncestor(focus,GA_ROOT),WM_NEXTDLGCTL,TRUE,FALSE);return;}PostMessageW(focus,WM_KEYDOWN,value,1);PostMessageW(focus,WM_KEYUP,value,0xc0000001);}

static HWND retainedFocus=nullptr;
static bool deliver(const std::string &line){
 installerWindow=nullptr;EnumWindows(findWindow,0);if(!installerWindow)return false;
 HWND popup=GetLastActivePopup(installerWindow);DWORD popupPid=0;GetWindowThreadProcessId(popup,&popupPid);
 if(IsWindowVisible(popup)&&installerProcess(popupPid))installerWindow=popup;
 DWORD thread=GetWindowThreadProcessId(installerWindow,nullptr),ownThread=GetCurrentThreadId();
 bool attached=thread!=ownThread&&AttachThreadInput(ownThread,thread,TRUE);
 SetForegroundWindow(installerWindow);
 GUITHREADINFO info{};info.cbSize=sizeof(info);GetGUIThreadInfo(thread,&info);
 HWND focus=info.hwndFocus;
 if(!focus||focus==installerWindow||GetAncestor(focus,GA_ROOT)!=installerWindow)focus=IsWindow(retainedFocus)&&GetAncestor(retainedFocus,GA_ROOT)==installerWindow?retainedFocus:GetNextDlgTabItem(installerWindow,nullptr,FALSE);
 if(!focus)focus=installerWindow;
 DWORD pid=0;GetWindowThreadProcessId(focus,&pid);
 if(!installerProcess(pid)){if(attached)AttachThreadInput(ownThread,thread,FALSE);return false;}
 SetFocus(focus);retainedFocus=focus;
 wchar_t focusClass[64];GetClassNameW(focus,focusClass,64);
 fprintf(stderr,"Games installer control %s -> owned process %lu, control %ls (%d)\n",line.rfind("text:",0)==0?"text":line.c_str(),static_cast<unsigned long>(pid),focusClass,GetDlgCtrlID(focus));fflush(stderr);
 if(line=="r1"||line=="l1"){
  HWND next=GetNextDlgTabItem(installerWindow,focus,line=="l1");
  if(next){SetFocus(next);retainedFocus=next;}else key(focus,VK_TAB,line=="l1");
  if(attached)AttachThreadInput(ownThread,thread,FALSE);
  return true;
 }
 // Never send synchronous messages while input queues are attached: an
 // installer can close its UI/thread during activation and wait for detach.
 if(attached)AttachThreadInput(ownThread,thread,FALSE);
 if(line=="primary"){
  wchar_t name[64];GetClassNameW(focus,name,64);
  if(_wcsicmp(name,L"Button")==0)PostMessageW(focus,BM_CLICK,0,0);else key(focus,VK_RETURN);
 }else if(line=="up")key(focus,VK_UP);else if(line=="down")key(focus,VK_DOWN);else if(line=="left")key(focus,VK_LEFT);else if(line=="right")key(focus,VK_RIGHT);
 else if(line.rfind("text:",0)==0){
  std::string bytes;for(size_t i=5;i+1<line.size();i+=2){char part[3]={line[i],line[i+1],0};char *end=nullptr;long v=strtol(part,&end,16);if(*end){if(attached)AttachThreadInput(ownThread,thread,FALSE);return true;}bytes+=char(v);}
  int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,bytes.data(),int(bytes.size()),nullptr,0);
  if(count>0&&count<=4096){std::wstring text(count,0);MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,bytes.data(),int(bytes.size()),text.data(),count);for(wchar_t c:text)PostMessageW(focus,WM_CHAR,c,1);}
 }
 return true;
}

int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int){
 int argc=0;LPWSTR *argv=CommandLineToArgvW(GetCommandLineW(),&argc);if(argc<3)return 64;
 wchar_t systemDrive[16]{},systemRoot[MAX_PATH]{};
 fprintf(stderr,"Games installer environment: SystemDrive=%lu characters, SystemRoot=%lu characters\n",static_cast<unsigned long>(GetEnvironmentVariableW(L"SystemDrive",systemDrive,16)),static_cast<unsigned long>(GetEnvironmentVariableW(L"SystemRoot",systemRoot,MAX_PATH)));fflush(stderr);
 std::wstring input=argv[1],command;for(int i=2;i<argc;i++){if(i>2)command+=L" ";command+=quote(argv[i]);}
 std::wstring first=argv[2];std::transform(first.begin(),first.end(),first.begin(),::towlower);msi=first==L"msiexec"||first==L"msiexec.exe";
 STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION process{};
 if(!CreateProcessW(nullptr,command.data(),nullptr,nullptr,FALSE,0,nullptr,nullptr,&startup,&process)){LocalFree(argv);return int(GetLastError());}
 LocalFree(argv);owned.insert(process.dwProcessId);CloseHandle(process.hThread);
 LARGE_INTEGER position{};DWORD code=STILL_ACTIVE,previousCode=STILL_ACTIVE;
 for(;;){
  descendants();GetExitCodeProcess(process.hProcess,&code);if(code!=previousCode){fprintf(stderr,"Games installer parent exit: %lu; owned processes: %zu\n",static_cast<unsigned long>(code),owned.size());fflush(stderr);previousCode=code;}
  installerWindow=nullptr;EnumWindows(findWindow,0);
  bool alive=false;for(DWORD pid:owned){HANDLE h=OpenProcess(SYNCHRONIZE,FALSE,pid);if(h){alive|=WaitForSingleObject(h,0)==WAIT_TIMEOUT;CloseHandle(h);}}
  if(code!=STILL_ACTIVE&&!alive&&!installerWindow)break;
  HANDLE file=CreateFileW(input.c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(file!=INVALID_HANDLE_VALUE){SetFilePointerEx(file,position,nullptr,FILE_BEGIN);std::string line;char c;DWORD got;LONGLONG completed=position.QuadPart;while(ReadFile(file,&c,1,&got,nullptr)&&got){position.QuadPart++;if(c=='\n'){if(!deliver(line))break;line.clear();completed=position.QuadPart;}else if(line.size()<16384)line+=c;}position.QuadPart=completed;CloseHandle(file);}
  Sleep(20);
 }
 CloseHandle(process.hProcess);return int(code);
}
