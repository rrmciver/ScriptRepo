On Error Resume Next
Dim UIResManager 
Dim Cache 
Dim CacheSize
CacheSize=5120
Set UIResManager = createobject("UIResource.UIResourceMgr")
Set Cache=UIResManager.GetCacheInfo()
Cache.TotalSize=CacheSize