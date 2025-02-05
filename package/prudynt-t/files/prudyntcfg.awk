#!/usr/bin/awk -f
##############################################
# functions always start with _
#
# flag o: 
#   1 = key / value mode
#   2 = array open
#   4 = question marks open
#   8 = comment after value
#   64 = error
#   128 = write
#   256 = finish
##############################################
function _s(q){
    o=or(o,q);
}
function _u(q){
    if(and(o,q)){o=xor(o,q)};
}
function _q(q){
    return and(o,q)!=0;
}
function _i(q){
    u="";
    for(i=0;i<q;i++){u=u"\t"}
    return u;
}
function _e(q){
    if(g){g=g"\n"}
    g=g""q;
}
function _w(y){
    # if y is set we uncomment the line else we create a new one
    u=_i(d);
    if(y){
        u=u"# "t": "r";"
    }else{
        if(!v){v=r}
        u=u""e": "v";"
    }
    if(n){u=u" # "n}
    _s(128);
    return u;
}
function _b(){
    # section does not exists, we need to create
    if(!v){return}
    d=split(s,j,".");
    for(k in j){
        if(m){m=m"."}
        m=m""j[k];
        if(p!=m&&(m~"^"p".*")){
            u=_i(k-1);
            _e(u""j[k]": {")
        }else{x=k}
    }
    _e(_w());
    for(d--;d>=x;d--){
        u=_i(d);
        _e(u"};");
        u=""
    }
    _s(128);
}
# split line by char
function _a(){
    for(i=1;i<=length($0);i++){
        c=substr($0,i,1);
        if(_q(4)&&c!="\""){
            # everything is allowed in quotation marks
            k=k""c;
        }else if(c==":"||c=="="){
            # here we set value flag
            _s(1);t=k;k="";
        }else if(c=="{"){
            if(!_q(2)){
                # section opener, current key(k) = this(t)
                d++;
                if(p){
                    p=p"."t;k="";t=""
                }else{
                    p=t;t=""
                }
            }else{
                # object opener in an array
            }
        }else if(c=="}"){
            if(!_q(2)){
                # section closer
                #
                # if the section is closed and the value should be set but does not exist.
                # we insert a new line here
                if(s==p&&f~"^set$"&&(!_q(128))){
                    if(v){_e(_w())}
                }
                if(s~"^"p"\\..*$"&&f~"^set$"&&(!_q(128))){
                    if(v){_b()}
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
            _s(2);
        }else if(c==")"){
            # array closer
            _i(2);
        }else if(_q(1)==1&&c=="\""){
            # opening / closing quotation marks, assign string value on close
            if(!_q(4)){_s(4);k=""}else{_u(4);r="\""k"\"";k=""}
        }else if(_q(1)&&c==";"){
            # value terminator ';'
            if(length(r)==0){r=k;k=""};
        }else if(_q(1)&&c=="#"){
            # comment at the end of the line
            _s(8);
        }else if(match(c,"[^[:space:]]")){
            k=k""c;
        }
    }
}
function _p() {
    # match key/value line in section also if commented out
    b=(s==p&&match($0,"^[[:space:]]*#[[:space:]]*"e"[[:space:]]*:.*"));
    if(length($0)&&((!match($0,"^[[:space:]]*#")&&!match($0,"^\\s*$")&&!match($0,"^version.*$"))||b)){
        # check if line is commented out
        if(b){sub("#([[:space:]]*)","",$0)}
        # value mode reset on each line
        # comment reset on each line
        _u(9);
        # current (k), value(r), comment(n) rest on each line
        k="";r="";n="";
        # call _a to analyze line
        _a();
        # if k is not empty here, it must be a (unterminated) value or comment
        if(length(k)>0){if(_q(8)){n=k}else{r=k}}
        # exact section and value match
        if(f~"^list$"&&!b&&(p==s||p~"^"s"\\..*$"||!s)&&p&&t&&r){
            print(p"."t"="r)
        }
        if(s==p&&e==t) {
            if(f~"^get$"&&!b){_s(256);print(r);exit;}
            if(f~"^set$"){if(v||b){$0=_w()}}
            if(f~"^unset$"){$0=_w(1)}
        }
    }
}

BEGIN {
	f=ARGV[1];
	s=ARGV[2];
    if((f~"^(get|set|unset)$"&&s)){
        i=split(s,j,".");
	    e=j[i];
        sub(/\.[[:alnum:]_]+$/,"",s)
    }
	v=ARGV[3];
	if(!f||(!(f~"^(get|set|unset|list)$"))||(!(f~"^list$")&&i==1&&s)){
		print "prudynt configuration helper v0.1";
		print "";
		print "Usage [get|set|list|unset] <section>.<setting> <value>";
		print "";
		print "\tget\treceive a value for <section>.<setting>";
		print "\tset\tset <value> for <section>.<setting>";
		print "\t\tif value is not provided but setting exists as comment, it will be uncomment";
		print "\tlist\tlist all configured <settings>. Can be limited by providing a <section>";
		print "\tunset\tcomment a <setting> if exists";
        f="";_s(320);exit;
	}
    
	for (i=ARGC;i>2;i--){ARGC--}
	ARGV[1]="/etc/config/prudynt.cfg";
}
{if(o<256){if(o<128){_p()};_e($0)}}
END{
    if(f~"^set$"&&(!_q(128))){
        # main section does not exists, we need to create
        _e("");_b()
    }
	if(_q(128)) {
        print g>ARGV[1]
	}
    if((_q(128)||_q(256))&&f){
        exit 0
    }
    exit 1
}