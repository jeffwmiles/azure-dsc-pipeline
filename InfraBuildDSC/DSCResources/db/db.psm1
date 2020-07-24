Configuration db {

    Import-DscResource -ModuleName PSDscResources

    File CTemp {
        Type            = "Directory"
        DestinationPath = "C:\Temp3"
        Ensure          = "Present"
    }
}