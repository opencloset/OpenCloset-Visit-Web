$ ->
  $("#query").datepicker(
    todayHighlight: true
    autoclose:      true
  ).on( 'changeDate', (e) ->
    ymd = $('#query').prop('value')
    window.location = "/timetable/#{ymd}"
  )

  $('.pre_category').each (i, el) ->
    keys_str   = $(el).data('category') || ''
    values_str = ( OpenCloset.category[i].str for i in keys_str.split(',') ).join(',')
    $(el).html( values_str )

  $('.pre_color').each (i, el) ->
    keys_str   = $(el).data('color') || ''
    values_str = ( OpenCloset.color[i] for i in keys_str.split(',') ).join(',')
    $(el).html( values_str )

  $('#btn-slot-open').click (e) ->
    ymd = $('#btn-slot-open').data('date-ymd')
    window.location = "/timetable/#{ymd}/open"

  updateTimeTablePerson = (btn) ->
    ub_id     = $(btn).data('id')
    ub_status = $(btn).data('status')
    url       = $("#timetable-data").data('url') + "/#{ ub_id }"
    $(btn)
      .removeClass('btn-primary')
      .removeClass('btn-danger')
      .removeClass('btn-warning')
      .removeClass('btn-success')
      .removeClass('btn-info')
      .removeClass('btn-inverse')
    if ub_status is 'visiting'
      $(btn).addClass('btn-info')

  $('.btn.timetable-person').each (i, el) ->
    updateTimeTablePerson(el)

  $('.btn.timetable-person').click (e) ->
    btn       = this
    ub_id     = $(btn).data('id')
    ub_status = $(btn).data('status')
    url       = $("#timetable-data").data('url') + "/#{ ub_id }.json"

    ub_status_new = ''
    if ub_status is 'visiting'
      ub_status_new = ''
    else
      ub_status_new = 'visiting'

    $(btn).data( 'status', ub_status_new )
    $.ajax url,
      type: 'PUT'
      data:
        id:     ub_id
        status: ub_status_new
        success: (data, textStatus, jqXHR) ->
          updateTimeTablePerson(btn)

  updateOrder = ( order_id, ymd, status_id, alert_target, success_cb ) ->
    #
    # 주문서의 상태 갱신
    #
    $.ajax "/api/order/#{order_id}.json",
      type: 'PUT'
      data:
        id:        order_id
        status_id: status_id
      success: (data, textStatus, jqXHR) ->
        #
        # 상태 변경에 성공
        #

        #
        # 최상단의 요약 정보 갱신
        #
        $.ajax "/api/gui/timetable/#{ymd}.json",
          type: 'GET'
          success: (data, textStatus, jqXHR) ->
            $('#count-all').html(data.all)
            $('#count-visited').html(data.visited)
            $('#count-notvisited').html(data.notvisited)
            success_cb() if success_cb
      error: (jqXHR, textStatus, errorThrown) ->
        OpenCloset.alert('danger', "주문서 상태 변경에 실패했습니다: #{jqXHR.responseJSON.error.str}", "##{alert_target}")

  enableStatus = (el) ->
    status_id = $(el).editable( 'getValue', true )
    switch status_id
      when 14 then enable = true # 방문예약
      when 12 then enable = true # 미방문
      when 13 then enable = true # 방문
      when 16 then enable = true # 치수측정
      when 17 then enable = true # 의류준비
      when 20 then enable = true # 탈의01
      when 21 then enable = true # 탈의02
      when 22 then enable = true # 탈의03
      when 23 then enable = true # 탈의04
      when 24 then enable = true # 탈의05
      when 25 then enable = true # 탈의06
      when 26 then enable = true # 탈의07
      when 27 then enable = true # 탈의08
      when 28 then enable = true # 탈의09
      when  6 then enable = true # 수선
      when 18 then enable = true # 포장
      else         enable = false
    if enable
      $(el).editable 'enable'
    else
      $(el).editable 'disable'

  #
  # 시간표내 각각의 주문서 상태 변경
  #
  $('.editable').each (i, el) ->
    available_status = [
      '방문예약',
      '미방문',
      '방문',
      '치수측정',
      '의류준비',
      '탈의01',
      '탈의02',
      '탈의03',
      '탈의04',
      '탈의05',
      '탈의06',
      '탈의07',
      '탈의08',
      '탈의09',
      '수선',
      '포장',
    ]
    $(el).editable(
      mode:        'inline'
      showbuttons: 'true'
      emptytext:   '상태없음'
      type:        'select'
      source:      ( { value: OpenCloset.status[i]['id'], text: i } for i in available_status )
      url: (params) ->
        storage      = $(el).closest('.people-box')
        order_id     = storage.data('order-id')
        alert_target = storage.data('target')
        ymd          = storage.data('ymd')
        status_id    = params.value
        updateOrder order_id, ymd, status_id, alert_target
      display: (value, sourceData) ->
        unless value
          $(this).empty()
          return
        mapped = {}
        ( mapped[v.id] = k ) for k, v of OpenCloset.status
        $(this).html mapped[value]
    )

  $('.editable').each (i, el) -> enableStatus(el)
  $('.editable').on 'save', (e, params) -> enableStatus(this)

  #
  # 각각의 주문서에서 다음 상태로 상태 변경
  #
  # 14 => 방문예약
  # 12 => 미방문
  # 13 => 방문
  # 16 => 치수측정
  # 17 => 의류준비
  #
  # 20 => 탈의01
  # 21 => 탈의02
  # 22 => 탈의03
  # 23 => 탈의04
  # 24 => 탈의05
  # 25 => 탈의06
  # 26 => 탈의07
  # 27 => 탈의08
  # 28 => 탈의09
  #
  #  6 => 수선
  # 18 => 포장
  # 19 => 결제대기
  #
  $('.people-box a.order-next-status').click (e) ->
    storage      = $(this).closest('.people-box')
    order_id     = storage.data('order-id')
    alert_target = storage.data('target')
    ymd          = storage.data('ymd')

    #
    # 주문서의 현재 상태
    #
    $.ajax "/api/order/#{order_id}.json",
      type:    'GET'
      success: (data, textStatus, jqXHR) ->
        switch parseInt(data.status_id)
          when 14 then status_id = 13 # 방문예약 -> 방문
          when 13 then status_id = 16 # 방문     -> 치수측정
          when 16 then status_id = 17 # 치수측정 -> 의류준비
          when 20 then status_id = 18 # 탈의01   -> 포장
          when 21 then status_id = 18 # 탈의02   -> 포장
          when 22 then status_id = 18 # 탈의03   -> 포장
          when 23 then status_id = 18 # 탈의04   -> 포장
          when 24 then status_id = 18 # 탈의05   -> 포장
          when 25 then status_id = 18 # 탈의06   -> 포장
          when 26 then status_id = 18 # 탈의07   -> 포장
          when 27 then status_id = 18 # 탈의08   -> 포장
          when 28 then status_id = 18 # 탈의09   -> 포장
          when  6 then status_id = 18 # 수선     -> 포장
          else return
        success_cb = () ->
          $(storage).find('.editable').editable( 'setValue', status_id, true )
          $(storage).find('.editable').each (i, el) -> enableStatus(el)
        updateOrder order_id, ymd, status_id, alert_target, success_cb
      error: (jqXHR, textStatus, errorThrown) ->
        OpenCloset.alert('danger', "현재 주문서 상태를 확인할 수 없습니다: #{jqXHR.responseJSON.error.str}", "##{alert_target}")
