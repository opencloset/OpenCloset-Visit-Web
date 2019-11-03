$ ->
  #
  # common fuction for OpenCloset
  #
  Window::OpenCloset =
    alert: (cls, msg, target) ->
      unless msg
        msg = cls
        cls = 'info'
      unless target
        target = '.main-content'
      # error, success, info
      $(target).prepend("<div class=\"alert alert-#{cls}\"><button class=\"close\" type=\"button\" data-dismiss=\"alert\">&times;</button>#{msg}</div>")

      #
      # scroll to element
      #
      # http://stackoverflow.com/questions/6677035/jquery-scroll-to-element#answer-6677069
      #
      $('html, body').animate({ scrollTop: $(target).offset().top }, 0)

    category:
      jacket:    { str: '자켓',     price: 10000 }
      pants:     { str: '팬츠',     price: 10000 }
      skirt:     { str: '스커트',   price: 10000 }
      shirt:     { str: '셔츠',     price: 5000  }
      blouse:    { str: '블라우스', price: 5000  }
      shoes:     { str: '구두',     price: 5000  }
      tie:       { str: '타이',     price: 0     }
      onepiece:  { str: '원피스',   price: 10000 }
      coat:      { str: '코트',     price: 10000 }
      waistcoat: { str: '조끼',     price: 5000  }
      belt:      { str: '벨트',     price: 2000  }
      bag:       { str: '가방',     price: 5000  }
      misc:      { str: '기타',     price: 0     }
    commify: (num) ->
      num += ''
      regex = /(^[+-]?\d+)(\d{3})/
      while (regex.test(num))
        num = num.replace(regex, '$1' + ',' + '$2')
      return num
    sendSMSValidation: (name, to, success_cb, error_cb) ->
      $.ajax "/api/sms/validation.json",
        type: 'POST'
        data:
          name: name
          to:   to
        success: (data, textStatus, jqXHR) ->
          success_cb( data, textStatus, jqXHR )
        error: (jqXHR, textStatus, errorThrown) ->
          error_cb( jqXHR, textStatus, errorThrown )

  #
  # return nothing
  #
  return
