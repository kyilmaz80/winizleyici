using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Diagnostics.Eventing.Reader;
using System.Linq;
using System.Text;
using System.Security.Principal;
using System.DirectoryServices.AccountManagement;
using System.Web.Script.Serialization;

namespace DNSClient
{
    class Program
    {
        public class Dns
        {
            public int? ProcessId { get; set; }
            public object dnsAddress { get; set; }
            public DateTime? timeCreated { get; set; }
        }

        static void Main(string[] args)
        {
            // Create an EventLog instance and assign its source.
            string source = "Microsoft-Windows-DNS-Client/Operational";
            string sid = UserPrincipal.Current.Sid.ToString();
            var eventId = "3006";
            var startTime = System.DateTime.Now.AddMinutes(-10);
            var endTime = System.DateTime.Now;
            var elConfig = new EventLogConfiguration(source);
            if (!elConfig.IsEnabled)
            {
                elConfig.IsEnabled = true;
                elConfig.SaveChanges();
            }

            //https://docs.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname?view=win10-ps
            var query = string.Format(@"*[System/EventID={0}] and *[System[TimeCreated[@SystemTime >= '{1}']]] and *[System[TimeCreated[@SystemTime <= '{2}']]] and *[System[Security[@UserID= '{3}']]]",
                eventId,
                startTime.ToUniversalTime().ToString("o"),
                endTime.ToUniversalTime().ToString("o"),
                sid);


            var elQuery = new EventLogQuery(source, PathType.LogName, query);
            var elReader = new EventLogReader(elQuery);

            List<Dns> respmsg = new List<Dns>();
            int i = 0;
            for (EventRecord eventInstance = elReader.ReadEvent(); eventInstance != null; eventInstance = elReader.ReadEvent())
            {
                if (eventInstance.Properties[1].Value.ToString() == "1")
                {
                    i++;
                    respmsg.Add(new Dns { dnsAddress = eventInstance.Properties[0].Value, ProcessId = eventInstance.ProcessId, timeCreated = eventInstance.TimeCreated });
                }
            }
 
            var groupedCustomerList = respmsg.GroupBy(_ => _.ProcessId).ToList();

            foreach (var group in groupedCustomerList)
            {
                Console.WriteLine("Process Id {0}", group.Key);
                Console.WriteLine("----");
                foreach (var item in group)
                {
                    Console.WriteLine("timecreated: " + item.timeCreated.Value.ToString() +  "  dnsaddress: " + item.dnsAddress);
                }
                Console.WriteLine(" ");
            }

            Console.ReadLine();
        }
    }
}
