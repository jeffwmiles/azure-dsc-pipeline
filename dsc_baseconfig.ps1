Configuration dsc_baseconfig {

    Import-DscResource -ModuleName InfraBuildDSC

Node $AllNodes.NodeName
    {
        # Everyone gets the baseline
        baseline baselineconfig {
        }

        if ($Node.Role -eq "Database"){
            db databaseconfig {
            }
        }

        if ($Node.Role -eq "WebServer"){
            web webconfig {
            }
        }

    } # End All Nodes
} # End Configuration