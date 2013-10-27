// Generated by CoffeeScript 1.6.2
(function() {
  $(function() {
    $('#clothe-id').focus();
    $('#btn-clear').click(function(e) {
      e.preventDefault();
      $('#clothes-list ul li').remove();
      $('#action-buttons').hide();
      return $('#clothe-id').focus();
    });
    $('#btn-clothe-search').click(function(e) {
      return $('#clothe-search-form').trigger('submit');
    });
    $('#clothe-search-form').submit(function(e) {
      var clothe_id;

      e.preventDefault();
      clothe_id = $('#clothe-id').val();
      $('#clothe-id').val('').focus();
      if (!clothe_id) {
        return;
      }
      return $.ajax("/clothes/" + clothe_id + ".json", {
        type: 'GET',
        dataType: 'json',
        success: function(data, textStatus, jqXHR) {
          var $html, compiled, html;

          if (!/^(대여중|연체중)/.test(data.status)) {
            if ($("#clothes-list li[data-clothe-id='" + data.id + "']").length) {
              return;
            }
            compiled = _.template($('#tpl-row-checkbox').html());
            $html = $(compiled(data));
            if (/대여가능/.test(data.status)) {
              $html.find('.order-status').addClass('label-success');
            }
            $('#clothes-list ul').append($html);
            return $('#action-buttons').show();
          } else {
            if ($("#clothes-list li[data-order-id='" + data.order_id + "']").length) {
              return;
            }
            compiled = _.template($('#tpl-row').html());
            $html = $(compiled(data));
            if (/연체중/.test(data.status)) {
              $html.find('.order-status').addClass('label-important');
            }
            if (data.overdue) {
              compiled = _.template($('#tpl-overdue-paragraph').html());
              html = compiled(data);
              $html.append(html);
            }
            return $('#clothes-list ul').append($html);
          }
        },
        error: function(jqXHR, textStatus, errorThrown) {
          return alert('error', jqXHR.responseJSON.error);
        },
        complete: function(jqXHR, textStatus) {}
      });
    });
    return $('#action-buttons').on('click', 'button:not(.disabled)', function(e) {
      var $this, clothes, status;

      $this = $(this);
      $this.addClass('disabled');
      status = $this.data('status');
      clothes = [];
      $('#clothes-list input:checked').each(function(i, el) {
        return clothes.push($(el).data('clothe-id'));
      });
      clothes = _.uniq(clothes);
      $.ajax("/clothes.json", {
        type: 'PUT',
        data: {
          status: status,
          clothes: clothes.join()
        },
        dataType: 'json',
        success: function(data, textStatus, jqXHR) {
          $('#clothes-list input:checked').each(function(i, el) {
            return $(el).closest('.row-checkbox').remove();
          });
          if (!$('#clothes-list .row-checkbox')) {
            $('#action-buttons').hide();
          }
          return alert('success', "" + clothes.length + "개의 항목이 " + status + " (으)로 변경되었습니다");
        },
        error: function(jqXHR, textStatus, errorThrown) {
          return alert('error', jqXHR.responseJSON.error);
        },
        complete: function(jqXHR, textStatus) {
          return $this.removeClass('disabled');
        }
      });
      return $('#clothe-id').focus();
    });
  });

}).call(this);
