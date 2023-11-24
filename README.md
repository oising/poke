# Poke

(build CI is broken, apologies)

[![Build status](https://ci.appveyor.com/api/projects/status/0gil31jtywx1c849?svg=true)](https://ci.appveyor.com/project/oising/poke)

### PowerShellGallery

[https://www.powershellgallery.com/packages/poke/]

Here you'll find examples of how to peek and poke objects using the Poke module.

### Version History

* 1.1.2 - fixes sort alias clash on *nix (thanks @fsackur)
* 1.1   - adds support for invoking methods with ref/out parameters ([ref])
* 1.0.2 - readonly fields are now settable like regular fields
* 1.0.1 - Compatibility fixes for v3 beta / .net 4.5
* 1.0   - Initial release
    
### Examples

```powershell
# peek at a Job instance using pipeline syntax
$job = start-job { 42 } | peek
$job | get-member
```
which results in the new extended output format for get-member:
```
   TypeName:
Pokeable.System.Management.Automation.PSRemotingJob#676f9716-c167-47c6-ab0d-4d8cedbbe44d

Name                            Modifier  MemberType Definition
----                            --------  ---------- ----------
Equals                          public    Method     bool Equals(System.Object obj)
GetHashCode                     public    Method     int GetHashCode()
GetType                         public    Method     type GetType()
CheckDisconnectedAndUpdateState private   Method*    void CheckDisconnectedAndUpdateState(System....
CommonInit                      private   Method*    void CommonInit(int throttleLimit, System.Co...
ConnectJob                      internal  Method*    void ConnectJob(guid runspaceInstanceId)
ConnectJobs                     internal  Method*    void ConnectJobs()
ConstructLocation               private   Method*    string ConstructLocation()
Dispose                         protected Method*    void Dispose(bool disposing)
FindDisconnectedChildJob        private   Method*    System.Management.Automation.PSRemotingChild...
GetAssociatedPowerShellObject   internal  Method*    powershell GetAssociatedPowerShellObject(gui...
GetJobsForComputer              internal  Method*    System.Collections.Generic.List[System.Manag...
GetJobsForOperation             internal  Method*    System.Collections.Generic.List[System.Manag...
GetJobsForRunspace              internal  Method*    System.Collections.Generic.List[System.Manag...
GetRunspaces                    internal  Method*    System.Collections.Generic.IEnumerable`1[[Sy...
HandleChildJobStateChanged      private   Method*    void HandleChildJobStateChanged(System.Objec...
HandleJobUnblocked              private   Method*    void HandleJobUnblocked(System.Object sender...
InternalStopJob                 internal  Method*    void InternalStopJob()
SetStatusMessage                private   Method*    void SetStatusMessage()
StopJob                         public    Method*    void StopJob()
SubmitAndWaitForConnect         private   Method*    void SubmitAndWaitForConnect(System.Collecti...
ToString                        public    Method*    string ToString()
__GetBaseObject                 -         Method*    System.Management.Automation.PSRemotingJob, ...
__GetModuleInfo                 -         Method*    psmoduleinfo __GetModuleInfo()
atleastOneChildJobFailed        private   Field*     bool atleastOneChildJobFailed
blockedChildJobsCount           private   Field*     int blockedChildJobsCount
CanDisconnect                   internal  Property*  bool CanDisconnect { get; set; }
disconnectedChildJobsCount      private   Field*     int disconnectedChildJobsCount
finishedChildJobsCount          private   Field*     int finishedChildJobsCount
HasMoreData                     public    Property*  bool HasMoreData { get; set; }
HideComputerName                internal  Property*  bool HideComputerName { get; set; }
isDisposed                      private   Field*     bool isDisposed
Location                        public    Property*  string Location { get; set; }
moreData                        private   Field*     bool moreData
StatusMessage                   public    Property*  string StatusMessage { get; set; }
throttleManager                 private   Field*     System.Management.Automation.Remoting.Thrott...
_stopIsCalled                   private   Field*     bool _stopIsCalled
_syncObject                     private   Field*     System.Object _syncObject
```

You can call methods, set fields and properties (if they have setters - it doesn't matter if they're private, protected or internal.)

You can proxy Types as well as instances:
```powershell
# proxy a public type by piping it
$type = [text.stringbuilder] | peek
```
```
   TypeName: Pokeable.System.RuntimeType#System.Text.StringBuilder

Name             Modifier MemberType Definition
----             -------- ---------- ----------
Equals           public   Method     bool Equals(System.Object obj)
GetHashCode      public   Method     int GetHashCode()
GetType          public   Method     type GetType()
FormatError      private  Method*    static void FormatError()
ThreadSafeCopy   private  Method*    static void ThreadSafeCopy(System.Char*, mscorlib, Version=4...
ToString         public   Method*    string ToString()
__CreateInstance -        Method*    .ctor (), .ctor (int capacity), .ctor (string value), .ctor ...
__GetBaseObject  -        Method*    type __GetBaseObject()
__GetModuleInfo  -        Method*    psmoduleinfo __GetModuleInfo()
CapacityField    private  Field*     string CapacityField
DefaultCapacity  internal Field*     int DefaultCapacity
MaxCapacityField private  Field*     string MaxCapacityField
MaxChunkSize     internal Field*     int MaxChunkSize
StringValueField private  Field*     string StringValueField
ThreadIDField    private  Field*     string ThreadIDField
```
Peeking at non-public types:
```powershell
# nonpublic types can't be specified using type literal
# syntax, so in this case you should use the -name parameter
$type = peek -name MS.Internal.Xml.XPath.XPathParser

# nonpublic objects returned from methods, properties or fields
# are not "peeked" themselves, so you may need to peek the return value:
$manager = peek (start-job { 42 } | peek).throttlemanager
$manager.throttlelimit = 64 # bump throttle limit ;)
```
Of course, you can peek instances too:
```powershell
$sb = new-object system.text.stringbuilder
$proxy = peek $sb
$proxy | gm
```
```
   TypeName: Pokeable.System.Text.StringBuilder#45f12364-1906-45b3-b48b-a77acd81e3f0

Name                                                     Modifier MemberType Definition
----                                                     -------- ---------- ----------
GetHashCode                                              public   Method     int GetHashCode()
GetType                                                  public   Method     type GetType()
Append                                                   public   Method*    System.Text.StringBu...
AppendFormat                                             public   Method*    System.Text.StringBu...
AppendHelper                                             private  Method*    void AppendHelper(st...
AppendLine                                               public   Method*    System.Text.StringBu...
Clear                                                    public   Method*    System.Text.StringBu...
CopyTo                                                   public   Method*    void CopyTo(int sour...
EnsureCapacity                                           public   Method*    int EnsureCapacity(i...
Equals                                                   public   Method*    bool Equals(System.T...
ExpandByABlock                                           private  Method*    void ExpandByABlock(...
FindChunkForByte                                         private  Method*    System.Text.StringBu...
FindChunkForIndex                                        private  Method*    System.Text.StringBu...
Insert                                                   public   Method*    System.Text.StringBu...
InternalCopy                                             internal Method*    void InternalCopy(Sy...
MakeRoom                                                 private  Method*    void MakeRoom(int in...
Next                                                     private  Method*    System.Text.StringBu...
Remove                                                   private  Method*    System.Text.StringBu...
Replace                                                  public   Method*    System.Text.StringBu...
ReplaceAllInChunk                                        private  Method*    void ReplaceAllInChu...
ReplaceBufferAnsiInternal                                internal Method*    void ReplaceBufferAn...
ReplaceBufferInternal                                    internal Method*    void ReplaceBufferIn...
ReplaceInPlaceAtChunk                                    private  Method*    void ReplaceInPlaceA...
StartsWith                                               private  Method*    bool StartsWith(Syst...
System.Runtime.Serialization.ISerializable.GetObjectData private  Method*    void System.Runtime....
ToString                                                 public   Method*    string ToString()
VerifyClassInvariant                                     private  Method*    void VerifyClassInva...
__GetBaseObject                                          -        Method*    System.Text.StringBu...
__GetModuleInfo                                          -        Method*    psmoduleinfo __GetMo...
Capacity                                                 public   Property*  int Capacity { get; ...
Chars                                                    public   Property*  char Chars { get; se...
Length                                                   public   Property*  int Length { get; se...
MaxCapacity                                              public   Property*  int MaxCapacity { ge...
m_ChunkChars                                             internal Field*     char[] m_ChunkChars
m_ChunkLength                                            internal Field*     int m_ChunkLength
m_ChunkOffset                                            internal Field*     int m_ChunkOffset
m_ChunkPrevious                                          internal Field*     System.Text.StringBu...
m_MaxCapacity                                            internal Field*     int m_MaxCapacity
```
Have fun!
