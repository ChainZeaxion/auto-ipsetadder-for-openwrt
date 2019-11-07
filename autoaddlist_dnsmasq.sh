#!/bin/sh
stdbuf -oL tail -F /tmp/dnsmasq.log | awk  -F "[, ]+" '/reply/{
ip=$8;
if (ip=="")
{
next;
}
if (index(ip,"<CNAME>")!=0)
{
if (cname==1)
{
    next;
}
cname=1;
domain=$6;
#第一次cname时锁定域名，防止解析cname对其改动
next;
}
#以上获得上行是否为cname，本行不是cname执行以下内容
#lastdomain记录上次非cname的域名，与本次域名对比
if(lastdomain!=$6){
    for (ipindex in ipcache)
    {
        delete ipcache[ipindex];
    }
    ipcount=0;
    createpid=1;
#上行非cname，并且不是同cname解析域名的多个ip，更新域名，清理同域名免试flag
if (cname!=1)
{
    domain=$6;
    testall=0;
}}
ipcount++;
cname=0;
lastdomain=$6
#去除非ipv4
if (index(ip,".")==0)
{
    next;
}
#不重复探测ip
if (!(ip in a))
{  
    #在gfwlist的chinaip警告，和忽略gfwlist中的ip
    "ipset test gfwlist "ip" 2>&1"| getline ipset;
    close("ipset test gfwlist "ip" 2>&1");
    if (index(ipset,"Warning")!=0){
        "ipset test china "ip" 2>&1"| getline ipset;
        close("ipset test china "ip" 2>&1");
        if (index(ipset,"Warning")!=0){
            print("warning china "ip" "domain" is in gfwlist")
        }else{
            print(ip" "domain" is in gfwlist pass");
        }
        next;
    }
#包数>12的同域名放过
if (passdomain==domain)
{
    print(ip" "domain" pass by same domain ok");
    a[ip]=domain;
    next;
}
#ip压入缓存，用于未检测到443/80的缓存
ipcache[ipcount]=ip;
if (testall==0){
    tryhttps=0;
    tryhttp=0;
    #探测 nf_conntrack 的443/80
    while ("grep "ip" /proc/net/nf_conntrack"| getline ret > 0)
    {
        split(ret, b," +");
        split(b[11], pagnum,"=");
        #包数>12的放过
        if (pagnum[2]>12)
        {
            print("pass by packets="pagnum[2]" "ip" "domain);
            for (ipindex in ipcache)
            {
                a[ipcache[ipindex]]=domain;
                delete ipcache[ipindex];
            }
            passdomain=domain;
            close("grep "ip" /proc/net/nf_conntrack");
            ipcount--;
            next;
        }
        if (b[8]=="dst="ip)
        {
            if (b[10]=="dport=443"){
                tryhttps=1;
                break;
            }
            else if (b[10]=="dport=80"){
                tryhttp=1;
            }
        }
    }
    close("grep "ip" /proc/net/nf_conntrack");
}else{
    if (testall==443)
    {
        tryhttps=1
    }else{
        tryhttp=1
    }
}
if (tryhttps==1)
{   if (createpid==1)
    {
        print "">"/tmp/run/"domain
        close("/tmp/run/"domain);
        print("create"domain);
        print(ip" "domain" 443"ipcount-1);
        a[ip]=domain;
        #正在使用的ip用最大延迟，最后探测，减少打断tcp的可能
        system("testip.sh "ip" "domain" 443 "ipcount-1" &");
        delete ipcache[ipcount];
        createpid=0;
    }
    #未检测到443/80同域名缓存的ip进行测试，ipindex-1为测试延迟时间
    for (ipindex in ipcache){
        print(ipcache[ipindex]" "domain" 443 "ipindex-1);
        a[ipcache[ipindex]]=domain;
        system("testip.sh "ipcache[ipindex]" "domain" 443 "ipindex-1" &");
        delete ipcache[ipindex];
    }
    #后续同域名ip免nf_conntrack测试
    testall=443;
}
else if (tryhttp==1)
{   
    if (createpid==1)
    {
        print "">"/tmp/run/"domain
        close("/tmp/run/"domain);
        print("create"domain);
        print(ip" "domain" 80 "ipcount-1);
        a[ip]=domain;
        system("testip.sh "ip" "domain" 80 "ipcount-1" &");
        delete ipcache[ipcount];
        createpid=0;
    }
    for (ipindex in ipcache){
        print(ipcache[ipindex]" "domain" 80 "ipindex-1);
        a[ipcache[ipindex]]=domain;
        system("testip.sh "ipcache[ipindex]" "domain" 80 "ipindex-1" &");
        delete ipcache[ipindex];
    }
    testall=80;
}}
}'