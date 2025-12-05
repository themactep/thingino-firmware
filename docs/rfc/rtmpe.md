# RTMPE

This document is a clean-room specification of the RTMP "Encryption"
scheme called RTMPE.  It contains industry-standard crypto primitives,
ARC4, HMACSHA256 and Diffie-Hellman.  The specification was created
by reviewing the source code of rtmpdump v1.6.

Academic and other discussion is invited.  Distribution of this document
is unlimited and encouraged.  Implementations even more so.

More info: http://lkcl.net/rtmp

## Revisions

```
23 may 2009: first draft
24 may 2009: added analysis section concluding algorithm is like SSL
25 may 2009: renamed "key" to "const".  explicitly mention lengths in notes.
27 may 2009: corrections in use of Get*GenuineConst fns (thanks to KG)
```

## Conventions

- `data[x:y]` means "bytes x through y, inclusive" - like in python
- `x+y on bytes` means "append the two byte streams, consecutively"
- `data[x]` means "the byte offset by x" - like in python.
- `/* ... */` means comments.
- `bigendian32(x)` means create 4 bytes in big-endian order, from a 32-bit integer.


## Constants

```
RTMP_SIG_SIZE = 1536
SHA256DL = 32 /* SHA 256-byte Digest Length */

RandomCrud = {
    0xf0, 0xee, 0xc2, 0x4a,
    0x80, 0x68, 0xbe, 0xe8, 0x2e, 0x00, 0xd0, 0xd1,
    0x02, 0x9e, 0x7e, 0x57, 0x6e, 0xec, 0x5d, 0x2d,
    0x29, 0x80, 0x6f, 0xab, 0x93, 0xb8, 0xe6, 0x36,
    0xcf, 0xeb, 0x31, 0xae
}

SWFVerifySig = { 0x1, 0x1 }

/* data in quotes does not include quotes as part of data */
GenuineFMSConst = "Genuine Adobe Flash Media Server 001" /* 36 bytes long */
GenuineFPConst  = "Genuine Adobe Flash Player 001" /* 30 bytes long */

GenuineFMSConstCrud = GenuineFMSConst + RandomCrud
GenuineFPConstCrud = GenuineFPConst + RandomCrud
```


## GetServerDHOffset

The purpose of this function is to calculate the offset of the Server's
Diffie-Hellmann key.

Its input is 4 consecutive bytes.

    offset = byte[0] + byte[1] + byte[2] + byte[3]
    offset = modulo(offset,632)
    offset = offset + 8

For sanity, the offset should be no bigger than (767-128)

## GetServerGenuineConstDigestOffset

The purpose of this function is to calculate the offset of the Server's
Digest.

Input data is 4 consecutive bytes.

    offset = byte[0] + byte[1] + byte[2] + byte[3]
    offset = modulo(offset,728)
    offset = offset + 776

For sanity, the offset should be no bigger than (1535-32)

## GetClientDHOffset

The purpose of this function is to calculate the offset of the client's
Diffie-Hellmann key.

Input data is 4 consecutive bytes.

    offset = byte[0] + byte[1] + byte[2] + byte[3]
    offset = modulo(offset,632)
    offset = offset + 772

For sanity, the offset should be no bigger than (RTMP_SIG_SIZE-128-4)

## GetClientGenuineConstDigestOffset

The purpose of this function is to calculate the offset of the client's
Digest.

Input data is 4 consecutive bytes.

    offset = byte[0] + byte[1] + byte[2] + byte[3]
    offset = modulo(offset,728)
    offset = offset + 12

For sanity, the offset should be no bigger than (771-32)


## Packet Format

The packets consist of a one byte command followed by a 1536 byte message

    Bytes    : Description
    -------    -----------
    0          Command
    1:1536     message of RTMP_SIG_SIZE bytes

## Client First Exchange

This is the first packet to be generated.
clientsig and clientsig2 are RTMP_SIG_SIZE bytes.
serversig and serversig2 are RTMP_SIG_SIZE bytes.

Note: Encryption is only supported on versions at least 9.0.115.0

Note: The 0x08 command-byte is not yet known.  It is understood
to involve further obfuscation of the Client and Server Digests,
and is understood to be implemented in Flash 10.

Command byte:

    0x06 if encrypted
    0x08 if further encrypted (undocumented)
    0x03 if unencrypted

Message:

    0:3        32-bit system time, network byte ordered (htonl)
    4:7        Client Version.  e.g. 0x09 0x0 0x7c 0x2 is 9.0.124.2
    8:11       Obfuscated pointer to "Genuine FP" key 
    12:1531    Random Data, 128-bit Diffie-Hellmann key and "Genuine FP" key.
    1532:1535  Obfuscated pointer to 128-bit Diffie-Hellmann key 

Calculate location of Diffie Hellmann Public Key and create it:

    dhpkl = GetClientDHoffset(clientsig[1532:1535])
    DHPrivateKeyC, DHPublicKeyC = DHKeyGenerate(128) /* 128-bit */
    clientsig[dhpkl:dhpkl+127] = DHPublicKeyC

Calculate location of Client Digest and create it:

    /* Note: the SHA digest message is calculated from the bytes of
       the message, excluding the 32-bytes where the digest itself goes.
       Note also that GenuineFPConst is 30 bytes long.
    */

    cdl = GetClientGenuineConstDigestOffset(clientsig[8:11])
    msg = clientsig[0:cdl-1] + clientsig[cdl+SHA256DL:RTMP_SIG_SIZE-1]
    clientsig[cdl:cdl+SHA256DL-1] = HMACsha256(msg, GenuineFPConst)

First Exchange:

    Send all 1537 bytes (command + clientsig) to the server;
    Read 1537 bytes (command + serversig) from the server.

Note that the exact circumstances under which "Message Format 1"
or "Message Format 2" are utilised is unknown.  It is therefore
necessary for clients to utilise the SHA verification to determine
which of the two message formats is being received (!)

Command byte:

    0x06 if encrypted - same as client request
    0x03 if unencrypted - same as client request

Message Format 1:

    0:3        32-bit system time, network byte ordered (htonl)
    4:7        Server Version.  e.g. 0x09 0x0 0x7c 0x2 is 9.0.124.2
    8:11       Obfuscated pointer to "Genuine FMS" key 
    12:1531    Random Data, 128-bit Diffie-Hellmann key and "Genuine FMS" key.
    1532:1535  Obfuscated pointer to 128-bit Diffie-Hellmann key 

Calculate location of Server Digest and compare it:

    /* Note that GenuineFMSConst is 36 bytes long. */
    sdl = GetClientGenuineConstDigestOffset(serversig[8:11])
    msg = serversig[0:sdl-1] + serversig[sdl+SHA256DL:RTMP_SIG_SIZE-1]
    Compare(serversig[sdl:sdl+SHA256DL-1], HMACsha256(msg, GenuineFMSConst))

Calculate location of Server Diffie Hellmann Public Key and get it:

    dhpkl = GetClientDHoffset(serversig[1532:1535])
    DHPublicKeyS = serversig[dhpkl:dhpkl+127]

Message Format 2:

    0:3        32-bit system time, network byte ordered (htonl)
    4:7        Server Version.  e.g. 0x09 0x0 0x7c 0x2 is 9.0.124.2
    8:767      Random Data and 128-bit Diffie-Hellmann key 
    768:771    Obfuscated pointer to 128-bit Diffie-Hellmann key 
    772:775    Obfuscated pointer to "Genuine FMS" key 
    776:1535   Random Data and "Genuine FMS" key.

Calculate location of Server Digest and compare it:

    /* Note that GenuineFMSConst is 36 bytes long. */
    sdl = GetServerGenuineConstDigestOffset(serversig[772:775])
    msg = serversig[0:sdl-1] + serversig[sdl+SHA256DL:RTMP_SIG_SIZE-1]
    Compare(serversig[sdl:sdl+SHA256DL-1], HMACsha256(msg, GenuineFMSConst))

Calculate location of Server Diffie Hellmann Public Key and get it:

    dhpkl = GetServerDHoffset(serversig[768:771])
    DHPublicKeyS = serversig[dhpkl:dhpkl+127]

Compute Diffie-Hellmann Shared Secret:

The key is only needed if encryption was negotiated.

    DHSharedSecret = DH(DHPrivateKeyC, DHPublicKeyS)

Compute SWFVerification token:

If a SWFHash is used, a SWFVerification response will need to
be calculated, and returned on-demand to a "ping" request.
SWFsize is the size of the SWF file.

Note: It is assumed that the reader is familiar enough with RTMP to
know what a "ping" is.  Where the ordinary ping type is 0x0006,
and the pong response is of type 0x0007, an SWF verification ping
is of type 0x001a and the SWF verification pong is of type 0x001b.
Packet sizes of type 0x001b are 44 bytes: 2 bytes for the type itself
and 42 bytes for the SWF verification response.

    swfvk = serversig[RTMP_SIG_SIZE-SHA256DL:RTMP_SIG_SIZE-1]
    SWFDigest = SWFVerifySig + bigendian32(SWFsize) + bigendian32(SWFsize) + HMACsha256(SWFHash, swfvk)

Initialise ARC4 Send / Receive Keys:

The ARC4 keys KeyIn and KeyOut are used to decrypt and encrypt
incoming and outgoing data, respectively.

    KeyIn  = ARC4Key(HMACsha256(DHPublicKeyS, DHSharedSecret)[0:15])
    KeyOut = ARC4Key(HMACsha256(DHPublicKeyC, DHSharedSecret)[0:15])

Explanation in words:

To calculate the ARC4 key for the data received by the client
(KeyIn), take the Server's initial 128-bit Diffie-Hellmann Secret
(from which the DH Shared Secret was calculated) and calculate
the HMACsha256 digest of that server's secret, using the DH
Shared Secret as the HMACsha256 key.

To calculate the ARC4 key for the data sent by the client
(KeyOut), take the Client's initial 128-bit Diffie-Hellmann Secret
(from which the DH Shared Secret was calculated) and calculate
the HMACsha256 digest of the client's secret, using the DH
Shared Secret as the HMACsha256 key.

Read Second Exchange:

Note: the second response appears to be read directly after the first
response, rather than the normal client-server arrangement of interleaving
client writes with server sends.

    Read 1536 bytes (serversig2) from the server.

Validate Second Response:

If Flash Player version 9 Hand-shaking is not being utilised,
then the server will have simply sent a copy of the client's
own previous packet back to it.  Otherwise, the client verifies
the response (the first four bytes of which are likely to be zero
if there was a validation error), as follows:

    digest = HMACsha256(DHPublicKeyC, GenuineFMSConstCrud)
    signature = HMACsha256(serversig2[0:RTMP_SIG_SIZE-SHA256DL-1], digest)
    Compare(signature, serversig2[RTMP_SIG_SIZE-SHA256DL:RTMP_SIG_SIZE-1])

Generate Second Response:

    clientsig2[0:RTMP_SIG_SIZE] = Random Data
    digest = HMACsha256(DHPublicKeyS, GenuineFPConstCrud)
    signature = HMACsha256(clientsig2[0:RTMP_SIG_SIZE-SHA256DL-1], digest)

Send Second Response:

    Write 1536 bytes (clientsig2) to server.

Update ARC4 Keys:

If encryption is enabled, then ONLY after the handshaking is completed
is the ARC4 keys applied to future communication.


## Analysis

The creation of the ARC4 encryption keys are created ultimately from
nothing more than a Diffie-Hellmann key exchange, excluding constants
and publicly-transferred information that is passed through hashing
algorithms, and is thus vulnerable to a man-in-the-middle attack.
There is no input into the algorithm from a secret key, password
or passphrase.  The same effect as this algorithm could therefore be
achieved with a well-known industry standard algorithm such as SSL
(if you removed SSL's protection against man-in-the-middle attacks).

The "verification" process involves nothing more than publicly-obtainable
information (the 32-byte SWFHash and the SWF size) and publicly-exchanged
data (the last 32 bytes of the first server response).

According to rtmpdump's README:

    Download the swf player you want to use for SWFVerification, unzip it using
        $ flasm -x file.swf
    It will show the decompressed filesize, use it for --swfsize
    Now generate the hash
        $ openssl sha -sha256 -hmac "Genuine Adobe Flash Player 001" file.swf
    and use the --swfhash "01234..." option to pass it.  e.g.
        $ ./rtmpdump --swfhash "123456..." --swfsize 987...

In other words, the "verification" algorithm basically links the
SWF file with the content that is being accessed through it.  The SWF file
unfortunately has to be made publicly available via web sites, and so
can be easily obtained.

Thus, the only "security" is given by linking the last 32 bytes of
the first server response in to the "verification" algorithm.
Unfortunately, this information was also generated with no passwords
or secret keys, and is transmitted in-the-clear.

Overall, then, the Adobe RTMPE algorithm tries to provide end-to-end
secrecy in exactly the same way that SSL provides end-to-end secrecy,
but the algorithm is subject to man-in-the-middle attacks, provides no
security, relies on publicly obtainable information and the algorithm
itself to obfuscate the content, and uses no authentication of any kind.
