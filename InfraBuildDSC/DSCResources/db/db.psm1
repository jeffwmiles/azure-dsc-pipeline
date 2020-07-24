Configuration db {

    Import-DscResource -ModuleName PSDscResources
    Import-DSCResource -ModuleName StorageDSC

    #Add disks for Oracle DB Server
    ## Disk1 is TemporaryStorage from Azure
    WaitforDisk Disk2
    {
        DiskId = 2
        RetryIntervalSec = 60
        RetryCount = 60
    }

    Disk DVolume
    {
        DiskId = 2
        DriveLetter = "D"
        FSLabel = "Database"
    }
}