On Error Resume Next
Dim UIResManager 
Dim Cache
Dim CacheSize
Set UIResManager = createobject("UIResource.UIResourceMgr")
Set Cache=UIResManager.GetCacheInfo()
Set CacheSize = Cache.TotalSize
If CacheSize >= 5120 Then wscript.echo "True"