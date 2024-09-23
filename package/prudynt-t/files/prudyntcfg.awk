#!/usr/bin/awk -f
# write line if y is set, it's commented out
function w(y){
    for(i=0;i<d;i++){u=u"\t"};
    if(y){
        u=u"# "t": "r";"
    }else{
        if(!length(v)){v=r}
        u=u""e": "v";"
    }
    if(length(n)){u=u" # "n}
    o=or(o,128);
    return u;
}
function b(){
    # section does not exists, we need to create
    d=split(s,j,".");
    for(k in j){
        if(length(m)){m=m"."}
        m=m""j[k];
        if(p!=m&&(m~"^"p".*")){
            u="";
            for(i=1;i<k;i++){u=u"\t"}
            g[h++]=u""j[k]": {"
        }else{x=k}
    }
    u="";g[h++]=w();
    for(d--;d>=x;d--){
        u="";
        for(i=d;i>0;i--){u=u"\t"}
        g[h++]=u"};";u=""
    }   
}
# split line by char
function a(l){
    split(l,c,"");
    for(i=1;i<=length($0);i++){
        s(c[i]);
    }
}
# analyze char
function s(c){
    if(and(o,4)&&c!="\""){
        # everything is allowed in quotation marks
        k=k""c;
    }else if(c==":"||c=="="){
        # here we set value flag
        o=or(o,1);t=k;k="";
    }else if(c=="{"){
        if(!and(o,2)){
            # section opener, current key(k) = this(t)
            d++;
            if(length(p)>0){
                p=p"."t;k="";t=""
            }else{
                p=t;t=""
            }
        }else{
            # object opener in an array
        }
    }else if(c=="}"){
        if(!and(o,2)){
            # section closer
            #
            # if the section is closed and the value should be set but does not exist.
            # we insert a new line here
            if(s==p&&f~"^set$"&&(!and(o,128))){
                if(length(v)){g[h++]=w()}else{o=or(o,128)}
            }
            if(s~"^"p".*$"&&f~"^set$"&&(!and(o,128))){
                b();
            }            
            # remove last path element and cleanup current(t)
            if(sub(/\.[[:alnum:]]+$/,"",p)==0){
                p=""
            }
            t="";d--
        } else {
            # object closer in an array
        }
    }else if(c=="("){
        # array opener
        o=or(o,2);
    }else if(c==")"){
        # array closer
        o=xor(o,2);
    }else if(and(o,1)==1&&c=="\""){
        # opening / closing quotation marks, assign string value on close
        if(!and(o,4)){o=or(o,4);k=""}else{o=xor(o,4);r="\""k"\"";k=""}
    }else if(and(o,1)&&c==";"){
        # value terminator ';'
        if(length(r)==0){r=k;k=""};
    }else if(and(o,1)&&c=="#"){
        # comment at the end of the line
        o=or(o,8);
    }else if(match(c,"[^[:space:]]")){
        k=k""c;
    }
}
function p(l) {
    _m=(s==p&&match(l,"^[[:space:]]*#.*"e".*:.*"));
    if(length(l)&&((!match(l,"^[[:space:]]*#")&&!match(l,"^\s*$")&&!match(l,"^version.*$"))||_m)){
        # check if line is commented out
        if(_m){sub("#[[:space:]]", "",l)}
        # value mode reset on each line
        if(and(o,1)){o=xor(o,1)}
        # comment reset on each line
        if(and(o,8)){o=xor(o,8)}
        # current (k), value(r), comment(n) rest on each line
        k="";r="";n="";
        # call a to analyze character
        a(l);
        # if k is not empty here, it must be a (unterminated) value or comment
        if(length(k)>0){if(and(o,8)==8){n=k}else{r=k}}
        # exact section and value match
        if(f~"^list$"&&!_m&&(p==s||p~"^"s".*$"||length(s)==0)&&length(p)&&length(t)&&length(r)){
            o=or(o,128);
            print(p"."t"="r)
        }
        if(s==p&&e==t) {
            if(f~"^get$"&&!_m){o=or(o,256);print(r);exit;}
            if(f~"^set$"){if(length(v)||_m){$0=w()}else{o=or(o,128)}}
            if(f~"^unset$"){$0=w(1)}
        }
    }
}

BEGIN {
	f=ARGV[1];
	s=ARGV[2];
    if((f~"^[g|s]et|unset$"&&ARGV[2])){
        i=split(s,j,".");
	    e=j[i];sub(/\.[[:alnum:]]+$/,"",s)
    }
	v=ARGV[3];
	if(!ARGV[1]||(f~"^[g|s]et|unset$"&&!ARGV[2])||i==1){
		print "prudynt configuration helper v0.1";
		print "";
		print "Usage [get|set|list|unset] <section>.<setting> <value>";
		print "";
		print "\tget\treceive a value for <section>.<setting>";
		print "\tset\tset <value> for <section>.<setting>";
		print "\t\tif value is not provided but setting exists as comment, it will be uncomment";
		print "\tlist\tlist all configured <settings>. Can be limited by providing a <section>";
		print "\tunset\tcomment a <setting> if exists";
        o=or(o,320);f="";
		exit;
	}
	for (i=ARGC;i>2;i--){ARGC--}
	ARGV[1]="/etc/prudynt.cfg";
}
{if(!and(o,256)){p($0);g[h++]=$0}}
END{
    if(f~"^set$"&&(!and(o,128))){
        # main section does not exists, we need to create
        g[h++];b()
    }
	if(f~"^set$|^unset$") {
		for(i=0;i<h;i++) {
            print g[i]>ARGV[1]
		}
	}
    if((and(o,256)||and(o,128))&&!and(o,64)){
        exit 0
    }
    exit 1
}