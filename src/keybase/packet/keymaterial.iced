K = require('../../const').kb
triplesec = require 'triplesec'
{SHA512} = require '../../hash'
{Decryptor,native_rng} = triplesec.prng
{Packet} = require './base'
{pack,box} = require '../encode'
{make_esc} = require 'iced-error'
rsa = require '../../rsa'
{sign,verify} = require '../sign'
{bufeq_secure,bufferify} = require '../../util'

#=================================================================================

class KeyMaterial extends Packet

  constructor : ({@key, @timestamp, @rawkey}) ->
    super()
    @rawkey or= {}

  #--------------------------

  export_public : () ->
    pub = @key.pub.serialize()
    return { type : @key.type, pub, @timestamp }

  #--------------------------

  export_private : ({tsenc, asp}, cb) ->
    ret = @export_public()
    priv = @key.priv.serialize()

    if tsenc?
      await tsenc.run { data : priv, progress_hook : asp?.progress_hook() }, defer err, epriv
      if err? then ret = null
      else
        ret.priv = 
          data : epriv
          encryption : K.key_encryption.triplesec_v2
    else
      ret.priv = 
        data : priv
        encryption : K.key_encryption.none

    cb err, ret

  #--------------------------

  @alloc : (secret_tag, o) ->
    ret = null
    try
      ret = new KeyMaterial { 
        timestamp : o.key.timestamp, 
        rawkey:
          type : o.key.type
          pub : o.key.pub,
          priv : o.key.priv 
      }
      throw new Error "didn't a private key" if secret_tag and not ret.rawkey.priv?
    catch e
      err = e 
    [err, ret]

  #--------------------------

  ekid : () -> @key.ekid()

  #--------------------------

  alloc_public_key : ({progress_hook}, cb) ->
    switch @rawkey.type
      when K.public_key_algorithms.RSA
        [ err, @key ] = rsa.RSA.alloc { pub : @rawkey.pub }
      else
        err = new Error "unknown key type: #{@rawkey.type}"
    cb err

  #--------------------------

  verify_self_sig : ({progress_hook}, cb) ->
    body = @_self_sign_body()
    type = K.signatures.self_sign_key_keybase_username
    await verify { @key, @sig, body, type, progress_hook }, defer err
    cb err

  #--------------------------

  merge_private : (k2) -> @rawkey.priv = k2.rawkey.priv

  #--------------------------

  open : ({tsenc, asp}, cb) ->
    err = null
    if (k = @rawkey.priv)?
      switch k.encryption
        when K.key_encryption.triplesec_v1, K.key_encryption.triplesec_v2
          dec = new Decryptor { enc : tsenc }
          await dec.run { data: k.data, progress_hook : asp.progress_hook() }, defer err, raw
          dec.scrub()
        when K.key_encryption.none
          raw = k.data
        else
          err = new Error "Unknown key encryption type: #{k.encryption}"
      err = @key.read_priv raw unless err?
    cb err

  #--------------------------

#=================================================================================

exports.KeyMaterial = KeyMaterial

#=================================================================================

