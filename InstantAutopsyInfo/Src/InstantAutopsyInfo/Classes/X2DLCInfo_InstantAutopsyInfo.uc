class X2DLCInfo_InstantAutopsyInfo extends X2DownloadableContentInfo;

`include(InstantAutopsyInfo\Src\InstantAutopsyInfo\LoggerMacros.uci)

static event OnPostTemplatesCreated()
{
	`TRACE_ENTRY("");
	`INFO(class'Version'.static.GetDisplayString());
	`TRACE_EXIT("");
}