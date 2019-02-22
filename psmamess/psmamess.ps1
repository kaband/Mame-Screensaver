<#	
	.NOTES
	===========================================================================
	 Created with:  		PowerShell Studio 2019 5.6.156
	 Created by:			Justin Baker
	 Filename:			psmamess.ps1
	 Website:				https://github.com/kaband/PSMame-Screensaver
	===========================================================================
#>
param
(
	[parameter(Mandatory = $false, Position = 0)]
	[string]$ssmode,
	[parameter(Mandatory = $false)]
	[int]$romcount = 0,
	[parameter(Mandatory = $false)]
	[string]$inifile
)

[string]$mydir = (Get-Location).path

# Execute config if /c switch is passed. 
# Exit if /p is passed (no preview available). 
# /s continue normally
switch ($ssmode)
{
	{ $_ -match "^/c" } {
		#	$mydir = (Get-Location).path
		#	Start-Process -FilePath "$mydir\psmamesscfg.exe"
		exit
	}
	{ $_ -match "^/p" } {
		exit
	}
}

# Import ini file.  Should be in same dir as .scr file unless being overridden by inifile parameter
if (-not ($inifile))
{
	[psobject]$config = Get-Content -path "$mydir\psmamess.ini"
}
else
{
	[psobject]$config = Get-Content -path $inifile
}

# Snapshot path setup
[string]$snapshotdir = "$($env:TEMP)\PSMameSnapshot"
if (-Not (test-path $snapshotdir))
{
	try
	{
		New-Item -ItemType directory -Path "$($env:TEMP)\PSMameSnapshot" -ErrorAction Stop
	}
	catch
	{
		Exit
	}
}

$logfile = "$($env:TEMP)\psmamess.log"
[array]$cfgattributes = @("mamepath", "rompath", "romlistpath", "configpath", "nvrampath", "arguments", "runtime", "volume", "masterxml", "destinationxml")
[hashtable]$cfg = @{ }
[array]$cmdargs = @()
[array]$romlist = @()

# Get config settings from ini
foreach ($line in $config)
{
	foreach ($attribute in $cfgattributes)
	{
		$regex = "^\s{0,}($attribute)\s{0,}=\s{0,}(.*)\s{0,}"
		if ($line -match $regex)
		{
			switch ($Matches[1])
			{
				"mamepath" {
					$cfg.mamepath = $Matches[2]
				}
				"rompath" {
					$cfg.rompath = $Matches[2]
				}
				"romlistpath" {
					$cfg.romlistpath = $Matches[2]
				}
				"configpath" {
					$cfg.configpath = $Matches[2]
				}
				"nvrampath" {
					$cfg.nvrampath = $Matches[2]
				}
				"arguments" {
					$cfg.arguments = $Matches[2]
				}
				"runtime" {
					$cfg.runtime = $Matches[2]
				}
				"volume" {
					$cfg.volume = $Matches[2]
				}
				"masterxml" {
					$cfg.masterxml = $Matches[2]
				}
				"destinationxml" {
					$cfg.destinationxml = $Matches[2]
				}
			}
			break
		}
	}
}
$Cursor = [System.Windows.Forms.Cursor]::New()
$Cursor.Hide()
# Create cmd line argument string
if ($cfg.rompath)
{
	$cmdargs += " -rompath $($cfg.rompath)"
}
if ($cfg.configpath)
{
	$cmdargs += " -cfg_directory $($cfg.configpath)"
}
if ($cfg.nvrampath)
{
	$cmdargs += " -nvram_directory $($cfg.nvrampath)"
}
if ($cfg.runtime)
{
	$cmdargs += " -str $($cfg.runtime)"
}
if ($cfg.volume)
{
	$cmdargs += " -volume $($cfg.volume)"
}
# This directory should go in TEMP and will be used to store temporary snapshots during runtime
# Do not use the same snapshotdir mame uses. Snapshots get purged.
$cmdargs += " -snapshot_directory $snapshotdir"
if ($cfg.arguments)
{
	$cmdargs += " $($cfg.arguments)"
}
if ($cfg.masterxml -and $cfg.destinationxml)
{
	[bool]$Launchbox = $true
	[xml]$masterlist = get-content $cfg.masterxml -Encoding UTF8
}

$romlist += Get-Content $cfg.romlistpath
[int]$exittime = $cfg.runtime - 1
[int]$running = 1
[int]$i = 0

# Get rid of any old .out and .err files if present
Remove-Item -Path $env:TEMP\psmamess.out -Force -ErrorAction SilentlyContinue
Remove-Item -Path $env:TEMP\psmamess.err -Force -ErrorAction SilentlyContinue

# Main Loop
do
{
	# Select Game to play
	if ($romlist.count -gt 1)
	{
		$rnd = get-random -minimum 0 -maximum ($romlist.count - 1)
	}
	elseif ($romlist.count -eq 1)
	{
		$rnd = 0
	}
	else
	{
		exit
	}
	# Show cmd
	Add-Content -Path $logfile -value "$($cfg.mamepath) $($romlist[$rnd]) $cmdargs"
	# Run mame
	try
	{
		Start-Process -FilePath $cfg.mamepath -ArgumentList "$($romlist[$rnd]) $cmdargs" -RedirectStandardOutput $env:TEMP\psmamess.out -RedirectStandardError $env:TEMP\psmamess.err -Wait -ErrorAction Stop -WindowStyle Minimized
		$output = Get-Content $env:TEMP\psmamess.out
		$outputerr = Get-Content $env:TEMP\psmamess.err
		Add-Content -Path $logfile -Value $output -ErrorAction SilentlyContinue
		Add-Content -Path $logfile -Value $outputerr -ErrorAction SilentlyContinue
		
		if ((-not($output -match "\($exittime Seconds\)") -and $output -match "\(\d{1,3} Seconds\)") -or ($output -eq $null -and $outputerr -eq $null))
		{
			$running = 0
		}
		elseif ($outputerr -ne $null)
		{
			Add-Content -Path $logfile -value "$($romlist[$rnd]) - Something is wrong w. this rom"
			Remove-Item -Path $env:TEMP\psmamess.out -Force -ErrorAction SilentlyContinue
			Remove-Item -Path $env:TEMP\psmamess.err -Force -ErrorAction SilentlyContinue
		}
		else
		{
			Remove-Item -Path $env:TEMP\psmamess.out -Force -ErrorAction SilentlyContinue
			Remove-Item -Path $env:TEMP\psmamess.err -Force -ErrorAction SilentlyContinue
		}
	}
	catch
	{
		Add-Content -Path $logfile -value "$($romlist[$rnd]) - Something is wrong w. this rom"
	}
	
	# Get list of directories in Snapshot Path	
	$ssdirs = Get-ChildItem -Directory -Path $snapshotdir
	
	#Launchbox List Support
	# In game snapshots will add game to Launchbox list
	If ($Launchbox -eq $true)
	{
		$ccount = 0 # Change counter
		foreach ($ssdir in $ssdirs)
		{
			# Check to see if its just one file and its called final.png
			# Runtime mode for mame will always take a snapshot of its final screen - Does not indicate someone took a snapshot by button pres
			if ((Get-ChildItem $ssdir.fullname | Measure-Object).Count -le 1 -and (Test-Path -Path "$($ssdir.fullname)\final.png"))
			{
				Remove-Item -Path $ssdir.fullname -Recurse
			}
			# If Dir has more than 1 file (2 or more image files) then a snapshot was taken
			elseif ((Get-ChildItem $ssdir.fullname | Measure-Object).Count -gt 1)
			{
				[xml]$destinationlist = get-content $cfg.destinationxml -Encoding UTF8
				$element = $null
				$newgameinfo = $null
				
				# Make sure game is not already on list
				if (($destinationlist.LaunchBox.playlistgame | where { $_.GameFileName -match $ssdir.name } | measure-object).count -eq 0)
				{
					$newgameinfo = $masterlist.LaunchBox.playlistgame | where { $_.GameFileName -match $ssdir.name }
					[int]$nextnumber = ($destinationlist.LaunchBox.playlistgame | sort GameTitle | select -last 1).manualorder
					$nextnumber++
					
					$element = $destinationlist.LaunchBox.playlistgame[0].Clone()
					$element.GameId = $newgameinfo.GameId
					$element.LaunchBoxDbId = $newgameinfo.LaunchBoxDbId
					$element.GameTitle = $newgameinfo.GameTitle
					$element.GameFileName = $newgameinfo.GameFileName
					$element.GamePlatform = $newgameinfo.GamePlatform
					$element.ManualOrder = $nextnumber.ToString()
					
					# Add Game to list
					$destinationlist.DocumentElement.AppendChild($element)
					
					# Remove screenshots
					Remove-Item -Path $ssdir.fullname -Recurse
					$ccount++
				}
				else
				{
					Remove-Item -Path $ssdir.fullname -Recurse
				}
			}
		}
		
		# Number and save xml if changes were made
		if ($ccount -gt 0)
		{
			# Update numbering of the entire list
			$order = 1
			foreach ($game in ($destinationlist.launchbox.playlistgame | Sort GameTitle))
			{
				$game.manualorder = "$order"
				$order++
			}
			# Save File
			$destinationlist.Save($cfg.destinationxml)
		}
	}
	else
	{
		# Purge Temp Snapshot dir of snapshot taken at end of game runtime 
		foreach ($ssdir in $ssdirs)
		{
			Remove-Item -Path $ssdir.fullname -Recurse
		}
	}
	
	if ($romcount -gt 0)
	{
		if ($i -ge $romcount)
		{
			$running = 0
		}
		$i++
	}
}
while ($running -eq 1)