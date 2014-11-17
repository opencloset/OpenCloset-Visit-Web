$ ->
  $('.order-status').each (i, el) ->
    $(el).addClass OpenCloset.status[ $(el).data('status') ].css
    $(el).find('.order-status-str').html('연체중') if $(el).data('late-fee') > 0

  #
  # inline editable field
  #
  $('.editable').each (i, el) ->
    params =
      mode:        'inline'
      showbuttons: 'true'
      emptytext:   '비어있음'
      pk:          $('#profile-user-info-data').data('pk')
      url: (params) ->
        url = $('#profile-user-info-data').data('url')
        data = {}
        data[params.name] = params.value
        $.ajax url,
          type: 'PUT'
          data: data

    switch $(el).attr('id')
      when 'user-name'
        params.type    = 'text'
        params.success = (response, newValue) ->
          $('.user-name').each (i, el) ->
            $(el).html newValue
      when 'user-gender'
        params.type   = 'select'
        params.source = [
          { value: 'male',   text: '남자' },
          { value: 'female', text: '여자' },
        ]
        params.display = (value) ->
          switch value
            when 'male'   then value_str = '남자'
            when 'female' then value_str = '여자'
            else               value_str = ''
          $(this).html value_str
      when 'user-staff'
        params.type   = 'select'
        params.source = [
          { value: '0', text: '고객' },
          { value: '1', text: '직원' },
        ]
        params.display = (value) ->
          if typeof value == 'number'
            value = value.toString()
          switch value
            when '0' then value_str = '고객'
            when '1' then value_str = '직원'
            else          value_str = ''
          $(this).html value_str
      when 'user-comment'
        params.type = 'textarea'
      else
        params.type = 'text'

    $(el).editable params
